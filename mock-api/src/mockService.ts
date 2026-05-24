import { Contract, Interface, JsonRpcProvider, MaxUint256 } from "ethers";

import {
  type MockConfig,
  type TokenMeta,
  NATIVE_SENTINEL,
  ZERO_ADDRESS,
  normalizeAddress,
} from "./config.js";

const ERC20_ABI = [
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];

const APPROVE_INTERFACE = new Interface([
  "function approve(address spender, uint256 amount)",
]);
const SWAP_INTERFACE = new Interface([
  "function swapExactInput(address srcToken, address dstToken, uint256 amountIn, uint256 minAmountOut, address recipient)",
]);

const PERCENT_SCALE = 1_000_000n;
const HUNDRED_PERCENT = 100n * PERCENT_SCALE;

export class HttpError extends Error {
  constructor(
    readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export class MockApiService {
  private readonly provider: JsonRpcProvider;
  private readonly tokensByAddress: Map<string, TokenMeta>;

  constructor(private readonly config: MockConfig) {
    this.provider = new JsonRpcProvider(config.rpcUrl, config.chainIdNumber);
    this.tokensByAddress = new Map(
      config.tokens.map((token) => [token.address.toLowerCase(), token]),
    );
  }

  assertSupportedChain(chainId: string): void {
    if (chainId !== this.config.chainId) {
      throw new HttpError(400, "Unsupported chain");
    }
  }

  getSpotPrices(addresses: string[]): Record<string, string> {
    const uniqueTokens = new Map<string, TokenMeta>();

    for (const address of addresses) {
      const token = this.resolveToken(address);
      uniqueTokens.set(token.address, token);
    }

    return Object.fromEntries(
      [...uniqueTokens.values()].map((token) => [
        token.address,
        this.getSpotPrice(token).toString(),
      ]),
    );
  }

  async buildQuote(params: {
    src: string;
    dst: string;
    amount: string;
    includeTokensInfo: boolean;
    includeProtocols: boolean;
    includeGas: boolean;
  }): Promise<Record<string, unknown>> {
    const srcToken = this.resolveToken(params.src);
    const dstToken = this.resolveToken(params.dst);
    const amountIn = parseAmount(params.amount, "amount");

    if (srcToken.address === dstToken.address) {
      throw new HttpError(400, "Source and destination must differ");
    }

    const dstAmount = this.quoteExactInput(srcToken, dstToken, amountIn);
    await this.ensureSufficientLiquidity(dstToken, dstAmount);

    return this.buildSwapLikeResponse({
      srcToken,
      dstToken,
      dstAmount,
      includeTokensInfo: params.includeTokensInfo,
      includeProtocols: params.includeProtocols,
      includeGas: params.includeGas,
    });
  }

  async buildSwap(params: {
    src: string;
    dst: string;
    amount: string;
    from: string;
    receiver?: string;
    slippage: string;
    includeTokensInfo: boolean;
    includeProtocols: boolean;
    includeGas: boolean;
  }): Promise<Record<string, unknown>> {
    const srcToken = this.resolveToken(params.src);
    const dstToken = this.resolveToken(params.dst);
    const amountIn = parseAmount(params.amount, "amount");

    if (srcToken.address === dstToken.address) {
      throw new HttpError(400, "Source and destination must differ");
    }

    const from = normalizeAddress(params.from);
    const receiver = params.receiver ? normalizeAddress(params.receiver) : from;
    const slippage = parsePercent(params.slippage, "slippage");
    const dstAmount = this.quoteExactInput(srcToken, dstToken, amountIn);
    await this.ensureSufficientLiquidity(dstToken, dstAmount);

    const minAmountOut = applySlippage(dstAmount, slippage);
    const response = this.buildSwapLikeResponse({
      srcToken,
      dstToken,
      dstAmount,
      includeTokensInfo: params.includeTokensInfo,
      includeProtocols: params.includeProtocols,
      includeGas: params.includeGas,
    });

    const tx: Record<string, string | number> = {
      from,
      to: this.config.swapAddress,
      data: SWAP_INTERFACE.encodeFunctionData("swapExactInput", [
        srcToken.internalAddress,
        dstToken.internalAddress,
        amountIn,
        minAmountOut,
        receiver,
      ]),
      value: (srcToken.category === "native" ? amountIn : 0n).toString(),
    };

    if (params.includeGas) {
      tx.gas = this.config.gasLimit;
    }

    return {
      ...response,
      ...(params.includeGas ? { gas: this.config.gasLimit } : {}),
      tx,
    };
  }

  async getAllowance(
    tokenAddress: string,
    walletAddress: string,
  ): Promise<string> {
    const token = this.resolveToken(tokenAddress);

    if (token.category === "native") {
      throw new HttpError(400, "Native token does not require allowance");
    }

    const wallet = normalizeAddress(walletAddress);
    const contract = new Contract(
      token.internalAddress,
      ERC20_ABI,
      this.provider,
    );
    const allowance = await contract.allowance(wallet, this.config.swapAddress);
    return allowance.toString();
  }

  getApproveTransaction(
    tokenAddress: string,
    amount?: string,
  ): Record<string, string> {
    const token = this.resolveToken(tokenAddress);

    if (token.category === "native") {
      throw new HttpError(400, "Native token does not require approval");
    }

    const approvalAmount = amount ? parseAmount(amount, "amount") : MaxUint256;

    return {
      to: token.address,
      data: APPROVE_INTERFACE.encodeFunctionData("approve", [
        this.config.swapAddress,
        approvalAmount,
      ]),
      value: "0",
    };
  }

  private buildSwapLikeResponse(input: {
    srcToken: TokenMeta;
    dstToken: TokenMeta;
    dstAmount: bigint;
    includeTokensInfo: boolean;
    includeProtocols: boolean;
    includeGas: boolean;
  }): Record<string, unknown> {
    return {
      dstAmount: input.dstAmount.toString(),
      ...(input.includeTokensInfo
        ? {
            srcToken: this.toTokenInfo(input.srcToken),
            dstToken: this.toTokenInfo(input.dstToken),
          }
        : {}),
      ...(input.includeProtocols
        ? {
            protocols: [
              {
                token: input.srcToken.address,
                hops: [
                  {
                    part: 100,
                    dst: input.dstToken.address,
                    fromTokenId: 0,
                    toTokenId: 1,
                    protocols: [
                      {
                        name: "MOCK_FIXED_RATE",
                        part: 100,
                      },
                    ],
                  },
                ],
              },
            ],
          }
        : {}),
      ...(input.includeGas ? { gas: this.config.gasLimit } : {}),
    };
  }

  private toTokenInfo(token: TokenMeta): Record<string, string | number> {
    return {
      address: token.address,
      symbol: token.symbol,
      name: token.name,
      decimals: token.decimals,
    };
  }

  private resolveToken(address: string): TokenMeta {
    const normalized = normalizeAddress(address, true);
    const token = this.tokensByAddress.get(normalized.toLowerCase());

    if (!token) {
      throw new HttpError(400, "Unsupported token");
    }

    return token;
  }

  private getSpotPrice(token: TokenMeta): bigint {
    if (token.category === "native") {
      return scaleForDecimals(token.decimals);
    }

    const nativeToken = this.resolveToken(NATIVE_SENTINEL);
    return this.quoteExactInput(
      token,
      nativeToken,
      scaleForDecimals(token.decimals),
    );
  }

  private quoteExactInput(
    srcToken: TokenMeta,
    dstToken: TokenMeta,
    amountIn: bigint,
  ): bigint {
    const baseAmountOut =
      (amountIn * srcToken.usdPrice * scaleForDecimals(dstToken.decimals)) /
      (dstToken.usdPrice * scaleForDecimals(srcToken.decimals));

    const feeBps = getFeeBps(srcToken, dstToken);
    return (baseAmountOut * BigInt(10_000 - feeBps)) / 10_000n;
  }

  private async ensureSufficientLiquidity(
    dstToken: TokenMeta,
    amountOut: bigint,
  ): Promise<void> {
    const availableLiquidity =
      dstToken.category === "native"
        ? await this.provider.getBalance(this.config.swapAddress)
        : await new Contract(
            dstToken.internalAddress,
            ERC20_ABI,
            this.provider,
          ).balanceOf(this.config.swapAddress);

    if (availableLiquidity < amountOut) {
      throw new HttpError(400, "Insufficient liquidity");
    }
  }
}

function getFeeBps(srcToken: TokenMeta, dstToken: TokenMeta): number {
  const srcStable = srcToken.category === "stable";
  const dstStable = dstToken.category === "stable";

  if (srcStable && dstStable) {
    return 10;
  }

  if (srcToken.category === "btc" || dstToken.category === "btc") {
    return 35;
  }

  if (srcToken.category === "native" || dstToken.category === "native") {
    return 20;
  }

  return 25;
}

function scaleForDecimals(decimals: number): bigint {
  return 10n ** BigInt(decimals);
}

function parseAmount(value: string, fieldName: string): bigint {
  if (!/^\d+$/.test(value)) {
    throw new HttpError(400, `Invalid ${fieldName}`);
  }

  return BigInt(value);
}

function parsePercent(value: string, fieldName: string): bigint {
  if (!/^\d+(\.\d+)?$/.test(value)) {
    throw new HttpError(400, `Invalid ${fieldName}`);
  }

  const [wholePart, fractionPart = ""] = value.split(".");

  if (fractionPart.length > 6) {
    throw new HttpError(400, `Invalid ${fieldName}`);
  }

  const scaled =
    BigInt(wholePart) * PERCENT_SCALE +
    BigInt(fractionPart.padEnd(6, "0") || "0");

  if (scaled > HUNDRED_PERCENT) {
    throw new HttpError(400, `${fieldName} must be between 0 and 100`);
  }

  return scaled;
}

function applySlippage(amount: bigint, slippage: bigint): bigint {
  return (amount * (HUNDRED_PERCENT - slippage)) / HUNDRED_PERCENT;
}
