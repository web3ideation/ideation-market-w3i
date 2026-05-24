import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import test from "node:test";

import type { MockConfig, ProductionConfig } from "./config.js";
import { createApp, type MockApiServiceLike } from "./index.js";

const mockConfig: MockConfig = {
  mode: "mock",
  port: 0,
  oneInchBaseUrl: "https://api.1inch.dev",
  chainId: "11155111",
  chainIdNumber: 11155111,
  rpcUrl: "http://127.0.0.1:8545",
  swapAddress: "0x1111111111111111111111111111111111111111",
  gasLimit: 150000,
  tokens: [],
};

const productionConfig: ProductionConfig = {
  mode: "production",
  port: 0,
  oneInchBaseUrl: "https://api.1inch.dev",
  apiKey: "test-api-key",
};

test("GET /healthz returns mock runtime metadata", async () => {
  const app = createApp(mockConfig, { mockService: createMockService() });

  await withServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/healthz`);

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      status: "ok",
      mode: "mock",
      chainId: "11155111",
    });
  });
});

test("GET /price forwards deduplicated addresses to the mock service", async () => {
  let observedAddresses: string[] | undefined;
  let observedChainId: string | undefined;

  const app = createApp(mockConfig, {
    mockService: createMockService({
      assertSupportedChain(chainId) {
        observedChainId = chainId;
      },
      getSpotPrices(addresses) {
        observedAddresses = addresses;
        return { "0xTokenA": "123", "0xTokenB": "456" };
      },
    }),
  });

  await withServer(app, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/price/v1.1/11155111/0xTokenA,0xTokenB,0xTokenA`,
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      "0xTokenA": "123",
      "0xTokenB": "456",
    });
  });

  assert.equal(observedChainId, "11155111");
  assert.deepEqual(observedAddresses, ["0xTokenA", "0xTokenB", "0xTokenA"]);
});

test("POST /price validates the request body", async () => {
  const app = createApp(mockConfig, { mockService: createMockService() });

  await withServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/price/v1.1/11155111`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tokens: "not-an-array" }),
    });

    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {
      error: "tokens must be an array of addresses",
    });
  });
});

test("GET /swap/v6.1/:chainId/quote passes compatibility flags", async () => {
  let observedParams: Record<string, unknown> | undefined;

  const app = createApp(mockConfig, {
    mockService: createMockService({
      async buildQuote(params) {
        observedParams = params;
        return { dstAmount: "999" };
      },
    }),
  });

  await withServer(app, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/swap/v6.1/11155111/quote?src=0xSource&dst=0xDest&amount=1000&includeTokensInfo=true&includeProtocols=true&includeGas=false`,
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { dstAmount: "999" });
  });

  assert.deepEqual(observedParams, {
    src: "0xSource",
    dst: "0xDest",
    amount: "1000",
    includeTokensInfo: true,
    includeProtocols: true,
    includeGas: false,
  });
});

test("GET /swap/v6.1/:chainId/swap preserves the receiver defaulting behavior", async () => {
  let observedParams: Record<string, unknown> | undefined;

  const app = createApp(mockConfig, {
    mockService: createMockService({
      async buildSwap(params) {
        observedParams = params;
        return {
          dstAmount: "777",
          tx: {
            from: "0xBuyer",
            to: "0xSwap",
            data: "0xabcdef",
            value: "0",
          },
        };
      },
    }),
  });

  await withServer(app, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/swap/v6.1/11155111/swap?src=0xSource&dst=0xDest&amount=500&from=0xBuyer&slippage=1.25&includeTokensInfo=false&includeProtocols=false&includeGas=true`,
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      dstAmount: "777",
      tx: {
        from: "0xBuyer",
        to: "0xSwap",
        data: "0xabcdef",
        value: "0",
      },
    });
  });

  assert.deepEqual(observedParams, {
    src: "0xSource",
    dst: "0xDest",
    amount: "500",
    from: "0xBuyer",
    receiver: undefined,
    slippage: "1.25",
    includeTokensInfo: false,
    includeProtocols: false,
    includeGas: true,
  });
});

test("approve helper routes delegate to the mock service", async () => {
  let allowanceRequest: string[] | undefined;
  let approvalRequest: string[] | undefined;

  const app = createApp(mockConfig, {
    mockService: createMockService({
      async getAllowance(tokenAddress, walletAddress) {
        allowanceRequest = [tokenAddress, walletAddress];
        return "42";
      },
      getApproveTransaction(tokenAddress, amount) {
        approvalRequest = [tokenAddress, amount ?? ""];
        return {
          to: tokenAddress,
          data: "0x095ea7b3",
          value: "0",
        };
      },
    }),
  });

  await withServer(app, async (baseUrl) => {
    const allowanceResponse = await fetch(
      `${baseUrl}/swap/v6.1/11155111/approve/allowance?tokenAddress=0xToken&walletAddress=0xWallet`,
    );
    assert.equal(allowanceResponse.status, 200);
    assert.deepEqual(await allowanceResponse.json(), { allowance: "42" });

    const transactionResponse = await fetch(
      `${baseUrl}/swap/v6.1/11155111/approve/transaction?tokenAddress=0xToken&amount=999`,
    );
    assert.equal(transactionResponse.status, 200);
    assert.deepEqual(await transactionResponse.json(), {
      to: "0xToken",
      data: "0x095ea7b3",
      value: "0",
    });
  });

  assert.deepEqual(allowanceRequest, ["0xToken", "0xWallet"]);
  assert.deepEqual(approvalRequest, ["0xToken", "999"]);
});

test("production mode proxies requests with server-side auth", async () => {
  let observedUrl: string | undefined;
  let observedMethod: string | undefined;
  let observedAuth: string | undefined;
  let observedBody: string | undefined;

  const app = createApp(productionConfig, {
    fetchImpl: async (input, init) => {
      observedUrl = String(input);
      observedMethod = init?.method;
      observedAuth = (init?.headers as Record<string, string>).Authorization;
      observedBody = init?.body as string | undefined;

      return new Response(JSON.stringify({ proxied: true }), {
        status: 202,
        headers: { "content-type": "application/json" },
      });
    },
  });

  await withServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/price/v1.1/1`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tokens: ["0xToken"] }),
    });

    assert.equal(response.status, 202);
    assert.deepEqual(await response.json(), { proxied: true });
  });

  assert.equal(observedUrl, "https://api.1inch.dev/price/v1.1/1");
  assert.equal(observedMethod, "POST");
  assert.equal(observedAuth, "Bearer test-api-key");
  assert.equal(observedBody, JSON.stringify({ tokens: ["0xToken"] }));
});

function createMockService(
  overrides: Partial<MockApiServiceLike> = {},
): MockApiServiceLike {
  return {
    assertSupportedChain() {},
    getSpotPrices() {
      return { "0xToken": "1" };
    },
    async buildQuote() {
      return { dstAmount: "1" };
    },
    async buildSwap() {
      return {
        dstAmount: "1",
        tx: {
          from: "0xBuyer",
          to: "0xSwap",
          data: "0x",
          value: "0",
        },
      };
    },
    async getAllowance() {
      return "0";
    },
    getApproveTransaction() {
      return { to: "0xToken", data: "0x095ea7b3", value: "0" };
    },
    ...overrides,
  };
}

async function withServer(
  app: ReturnType<typeof createApp>,
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const server = app.listen(0, "127.0.0.1");

  await new Promise<void>((resolve, reject) => {
    server.once("listening", () => resolve());
    server.once("error", reject);
  });

  try {
    const address = server.address() as AddressInfo;
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
}
