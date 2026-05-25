import "dotenv/config";

import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";
import { pathToFileURL } from "node:url";

import { type AppConfig, type MockConfig, loadConfig } from "./config.js";
import { HttpError, MockApiService } from "./mockService.js";

export type MockApiServiceLike = Pick<
  MockApiService,
  | "assertSupportedChain"
  | "getSpotPrices"
  | "buildQuote"
  | "buildSwap"
  | "getAllowance"
  | "getApproveTransaction"
>;

interface CreateAppOptions {
  mockService?: MockApiServiceLike;
  fetchImpl?: typeof fetch;
}

export function createApp(
  config: AppConfig = loadConfig(),
  options: CreateAppOptions = {},
): express.Express {
  const app = express();
  const mockService =
    config.mode === "mock"
      ? (options.mockService ?? new MockApiService(config as MockConfig))
      : null;
  const fetchImpl = options.fetchImpl ?? fetch;

  app.use(express.json());

  app.get("/healthz", (_req, res) => {
    res.json({
      status: "ok",
      mode: config.mode,
      ...(config.mode === "mock" ? { chainId: config.chainId } : {}),
    });
  });

  app.get(
    "/price/v1.1/:chainId/:addresses",
    asyncHandler(async (req, res) => {
      if (config.mode === "production") {
        await proxyRequest(config, req, res, fetchImpl);
        return;
      }

      const service = mockService as MockApiService;
      service.assertSupportedChain(req.params.chainId);

      const addresses = req.params.addresses.split(",").filter(Boolean);

      if (addresses.length === 0) {
        throw new HttpError(400, "At least one token address is required");
      }

      res.json(service.getSpotPrices(addresses));
    }),
  );

  app.post(
    "/price/v1.1/:chainId",
    asyncHandler(async (req, res) => {
      if (config.mode === "production") {
        await proxyRequest(config, req, res, fetchImpl);
        return;
      }

      const service = mockService as MockApiService;
      service.assertSupportedChain(req.params.chainId);

      const tokens = req.body?.tokens;

      if (
        !Array.isArray(tokens) ||
        !tokens.every((token) => typeof token === "string")
      ) {
        throw new HttpError(400, "tokens must be an array of addresses");
      }

      res.json(service.getSpotPrices(tokens));
    }),
  );

  app.get(
    "/swap/v6.1/:chainId/quote",
    asyncHandler(async (req, res) => {
      if (config.mode === "production") {
        await proxyRequest(config, req, res, fetchImpl);
        return;
      }

      const service = mockService as MockApiService;
      service.assertSupportedChain(req.params.chainId);

      res.json(
        await service.buildQuote({
          src: getQueryString(req, "src"),
          dst: getQueryString(req, "dst"),
          amount: getQueryString(req, "amount"),
          includeTokensInfo: getBooleanCompatibilityFlag(
            req,
            "includeTokensInfo",
          ),
          includeProtocols: getBooleanCompatibilityFlag(
            req,
            "includeProtocols",
          ),
          includeGas: getBooleanCompatibilityFlag(req, "includeGas"),
        }),
      );
    }),
  );

  app.get(
    "/swap/v6.1/:chainId/swap",
    asyncHandler(async (req, res) => {
      if (config.mode === "production") {
        await proxyRequest(config, req, res, fetchImpl);
        return;
      }

      const service = mockService as MockApiService;
      service.assertSupportedChain(req.params.chainId);

      res.json(
        await service.buildSwap({
          src: getQueryString(req, "src"),
          dst: getQueryString(req, "dst"),
          amount: getQueryString(req, "amount"),
          from: getQueryString(req, "from"),
          receiver: getOptionalQueryString(req, "receiver"),
          slippage: getQueryString(req, "slippage"),
          includeTokensInfo: getBooleanCompatibilityFlag(
            req,
            "includeTokensInfo",
          ),
          includeProtocols: getBooleanCompatibilityFlag(
            req,
            "includeProtocols",
          ),
          includeGas: getBooleanCompatibilityFlag(req, "includeGas"),
        }),
      );
    }),
  );

  app.get(
    "/swap/v6.1/:chainId/approve/allowance",
    asyncHandler(async (req, res) => {
      if (config.mode === "production") {
        await proxyRequest(config, req, res, fetchImpl);
        return;
      }

      const service = mockService as MockApiService;
      service.assertSupportedChain(req.params.chainId);

      res.json({
        allowance: await service.getAllowance(
          getQueryString(req, "tokenAddress"),
          getQueryString(req, "walletAddress"),
        ),
      });
    }),
  );

  app.get(
    "/swap/v6.1/:chainId/approve/transaction",
    asyncHandler(async (req, res) => {
      if (config.mode === "production") {
        await proxyRequest(config, req, res, fetchImpl);
        return;
      }

      const service = mockService as MockApiService;
      service.assertSupportedChain(req.params.chainId);

      res.json(
        service.getApproveTransaction(
          getQueryString(req, "tokenAddress"),
          getOptionalQueryString(req, "amount") ?? undefined,
        ),
      );
    }),
  );

  app.use(
    (error: unknown, _req: Request, res: Response, _next: NextFunction) => {
      if (error instanceof HttpError) {
        res.status(error.statusCode).json({ error: error.message });
        return;
      }

      if (error instanceof Error) {
        res.status(500).json({ error: error.message });
        return;
      }

      res.status(500).json({ error: "Unknown server error" });
    },
  );

  return app;
}

export function startServer(
  config: AppConfig = loadConfig(),
  options: CreateAppOptions = {},
) {
  const app = createApp(config, options);

  return app.listen(config.port, () => {
    console.log(`mock-api listening on :${config.port} in ${config.mode} mode`);
  });
}

if (isMainModule(import.meta.url)) {
  startServer();
}

function asyncHandler(
  handler: (req: Request, res: Response, next: NextFunction) => Promise<void>,
): (req: Request, res: Response, next: NextFunction) => void {
  return (req, res, next) => {
    void handler(req, res, next).catch(next);
  };
}

async function proxyRequest(
  config: AppConfig,
  req: Request,
  res: Response,
  fetchImpl: typeof fetch,
): Promise<void> {
  if (config.mode !== "production") {
    throw new HttpError(500, "Production proxy requested in mock mode");
  }

  const url = new URL(req.originalUrl, config.oneInchBaseUrl);
  const upstream = await fetchImpl(url, {
    method: req.method,
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${config.apiKey}`,
      ...(req.method !== "GET" ? { "Content-Type": "application/json" } : {}),
    },
    body: req.method === "GET" ? undefined : JSON.stringify(req.body),
  });

  const responseText = await upstream.text();
  const contentType =
    upstream.headers.get("content-type") ?? "application/json";

  res.status(upstream.status);
  res.type(contentType);
  res.send(responseText);
}

function getQueryString(req: Request, key: string): string {
  const value = req.query[key];

  if (typeof value !== "string") {
    throw new HttpError(400, `Missing ${key}`);
  }

  return value;
}

function getOptionalQueryString(req: Request, key: string): string | undefined {
  const value = req.query[key];
  return typeof value === "string" ? value : undefined;
}

function getBooleanCompatibilityFlag(req: Request, key: string): boolean {
  return req.query[key] === "true";
}

function isMainModule(moduleUrl: string): boolean {
  return (
    Boolean(process.argv[1]) &&
    moduleUrl === pathToFileURL(process.argv[1]).href
  );
}
