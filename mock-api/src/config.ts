import { getAddress } from "ethers";

export const NATIVE_SENTINEL = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const USD_SCALE = 100_000_000n;

export type RuntimeMode = "mock" | "production";
export type TokenCategory = "native" | "stable" | "btc" | "normal";

export interface TokenMeta {
  address: string;
  internalAddress: string;
  symbol: string;
  name: string;
  decimals: number;
  usdPrice: bigint;
  category: TokenCategory;
}

interface BaseConfig {
  mode: RuntimeMode;
  port: number;
  oneInchBaseUrl: string;
  corsAllowAll: boolean;
  corsAllowedOrigins: string[];
}

export interface MockConfig extends BaseConfig {
  mode: "mock";
  chainId: string;
  chainIdNumber: number;
  rpcUrl: string;
  swapAddress: string;
  gasLimit: number;
  tokens: TokenMeta[];
}

export interface ProductionConfig extends BaseConfig {
  mode: "production";
  apiKey: string;
}

export type AppConfig = MockConfig | ProductionConfig;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const mode = parseMode(env.API_MODE);
  const port = parseInteger(env.PORT ?? "3000", "PORT");
  const oneInchBaseUrl = env.ONEINCH_BASE_URL ?? "https://api.1inch.dev";
  const { corsAllowAll, corsAllowedOrigins } = parseCorsConfig(
    env.CORS_ALLOWED_ORIGINS,
  );

  if (mode === "production") {
    return {
      mode,
      port,
      oneInchBaseUrl,
      corsAllowAll,
      corsAllowedOrigins,
      apiKey: requireEnv(env.ONEINCH_API_KEY, "ONEINCH_API_KEY"),
    };
  }

  const chainId = env.MOCK_CHAIN_ID ?? "11155111";

  return {
    mode,
    port,
    oneInchBaseUrl,
    corsAllowAll,
    corsAllowedOrigins,
    chainId,
    chainIdNumber: parseInteger(chainId, "MOCK_CHAIN_ID"),
    rpcUrl: requireEnv(env.MOCK_RPC_URL, "MOCK_RPC_URL"),
    swapAddress: normalizeAddress(
      requireEnv(env.MOCK_SWAP_ADDRESS, "MOCK_SWAP_ADDRESS"),
    ),
    gasLimit: parseInteger(env.MOCK_GAS_LIMIT ?? "150000", "MOCK_GAS_LIMIT"),
    tokens: [
      {
        address: NATIVE_SENTINEL,
        internalAddress: ZERO_ADDRESS,
        symbol: "ETH",
        name: "Ether",
        decimals: 18,
        usdPrice: 2_500n * USD_SCALE,
        category: "native",
      },
      {
        address: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MERC20, "MOCK_TOKEN_MERC20"),
        ),
        internalAddress: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MERC20, "MOCK_TOKEN_MERC20"),
        ),
        symbol: "mERC20",
        name: "Mock ERC20",
        decimals: 18,
        usdPrice: 1n * USD_SCALE,
        category: "normal",
      },
      {
        address: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MUSDC, "MOCK_TOKEN_MUSDC"),
        ),
        internalAddress: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MUSDC, "MOCK_TOKEN_MUSDC"),
        ),
        symbol: "mUSDC",
        name: "Mock USDC",
        decimals: 6,
        usdPrice: 1n * USD_SCALE,
        category: "stable",
      },
      {
        address: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MWBTC, "MOCK_TOKEN_MWBTC"),
        ),
        internalAddress: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MWBTC, "MOCK_TOKEN_MWBTC"),
        ),
        symbol: "mWBTC",
        name: "Mock WBTC",
        decimals: 8,
        usdPrice: 100_000n * USD_SCALE,
        category: "btc",
      },
      {
        address: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MEURS, "MOCK_TOKEN_MEURS"),
        ),
        internalAddress: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MEURS, "MOCK_TOKEN_MEURS"),
        ),
        symbol: "mEURS",
        name: "Mock EURS",
        decimals: 2,
        usdPrice: 108_000_000n,
        category: "stable",
      },
      {
        address: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MUSDT, "MOCK_TOKEN_MUSDT"),
        ),
        internalAddress: normalizeAddress(
          requireEnv(env.MOCK_TOKEN_MUSDT, "MOCK_TOKEN_MUSDT"),
        ),
        symbol: "mUSDT",
        name: "Mock USDT",
        decimals: 6,
        usdPrice: 1n * USD_SCALE,
        category: "stable",
      },
    ],
  };
}

export function isNativeAddress(value: string): boolean {
  return value.toLowerCase() === NATIVE_SENTINEL.toLowerCase();
}

export function normalizeAddress(value: string, allowNative = false): string {
  if (allowNative && isNativeAddress(value)) {
    return NATIVE_SENTINEL;
  }

  try {
    return getAddress(value);
  } catch {
    throw new Error(`Invalid address: ${value}`);
  }
}

function parseMode(value: string | undefined): RuntimeMode {
  const normalized = (value ?? "mock").toLowerCase();

  if (normalized === "mock" || normalized === "production") {
    return normalized;
  }

  throw new Error(`Unsupported API_MODE: ${value}`);
}

function requireEnv(value: string | undefined, name: string): string {
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }

  return value;
}

function parseInteger(value: string, name: string): number {
  if (!/^\d+$/.test(value)) {
    throw new Error(`${name} must be an integer`);
  }

  return Number.parseInt(value, 10);
}

function parseCorsConfig(value: string | undefined): {
  corsAllowAll: boolean;
  corsAllowedOrigins: string[];
} {
  const normalized = value?.trim();

  if (!normalized) {
    return { corsAllowAll: false, corsAllowedOrigins: [] };
  }

  if (normalized === "*") {
    return { corsAllowAll: true, corsAllowedOrigins: [] };
  }

  return {
    corsAllowAll: false,
    corsAllowedOrigins: normalized
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  };
}
