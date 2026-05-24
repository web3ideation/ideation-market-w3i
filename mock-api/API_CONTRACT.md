# Mock API Contract

This document freezes the frontend-facing HTTP contract for the initial backend.

Scope:
- Preserve one frontend integration shape across environments.
- In production mode, proxy this subset to 1inch with server-side auth.
- In mock mode, return the same request and response shapes from deterministic local logic.

Out of scope:
- Full 1inch API parity.
- ABI-level compatibility with 1inch router contracts.
- Exact-output swap routing.

## Global Rules

Base path subset:
- `GET /price/v1.1/:chainId/:addresses`
- `POST /price/v1.1/:chainId`
- `GET /swap/v6.1/:chainId/quote`
- `GET /swap/v6.1/:chainId/swap`
- `GET /swap/v6.1/:chainId/approve/allowance`
- `GET /swap/v6.1/:chainId/approve/transaction`

Authentication:
- Frontend never sends a 1inch API key.
- Production backend injects `Authorization: Bearer <API_KEY>` server-side.
- Mock backend requires no upstream auth.

Native token convention:
- External native token sentinel is `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`.
- The backend translates between that sentinel and internal native token handling.
- The mock swap contract does not need to know about the sentinel.

Amount convention:
- All amounts are integer strings in smallest units.
- No decimal points are accepted.

Case and formatting:
- Query param values are treated as case-sensitive where 1inch expects booleans as strings.
- Addresses should be accepted case-insensitively and normalized internally.

Compatibility strategy:
- Fields marked `required by frontend` must be present in both production and mock responses.
- Fields marked `compatibility only` may be returned for parity but must not be required by the frontend.

Initial supported chains:
- Mock mode: Sepolia only.
- Production mode: pass through any 1inch-supported chain the frontend is configured to use.

## Token Set In Mock Mode

Initial supported assets:
- native ETH
- `mERC20`
- `mUSDC`
- `mWBTC`
- `mEURS`
- `mUSDT`

If a token is outside this set in mock mode:
- Spot price returns `400`.
- Quote returns `400`.
- Swap returns `400`.

## Error Envelope

Initial backend behavior may forward 1inch-style error bodies without attempting a universal custom envelope.

Minimum requirements:
- Preserve upstream HTTP status in production mode where practical.
- In mock mode, return a JSON body with a readable `error` string.
- Include backend logs sufficient to correlate failures.

Recommended mock error examples:

```json
{ "error": "Unsupported token" }
```

```json
{ "error": "Unsupported pair" }
```

```json
{ "error": "Insufficient liquidity" }
```

## Spot Price API

### `GET /price/v1.1/:chainId/:addresses`

Purpose:
- Used by the listing grid and local currency conversion.
- Must be cheap and deterministic in mock mode.

Path params:
- `chainId`: required.
- `addresses`: required comma-separated token addresses.

Request example:

```http
GET /price/v1.1/11155111/0xTokenA,0xTokenB,0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
```

Required request behavior:
- Accept one or many comma-separated addresses.
- Accept the native sentinel among addresses.
- Deduplicate addresses internally.

Response shape:
- JSON object keyed by token address.
- Values are price strings in native currency smallest units.

Response example:

```json
{
  "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE": "1000000000000000000",
  "0xMockUsdc": "500000000000000",
  "0xMockWbtc": "25000000000000000000"
}
```

Required by frontend:
- Object keys for every requested supported token.
- Numeric string values.

Compatibility only:
- None.

Mock-mode rules:
- Return fixed deterministic prices from the shared rate table.
- Use the same token registry as quote and swap.

### `POST /price/v1.1/:chainId`

Purpose:
- Same price surface as GET, but with token list in the body.

Path params:
- `chainId`: required.

Request body:

```json
{
  "tokens": [
    "0xTokenA",
    "0xTokenB",
    "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
  ]
}
```

Required request fields:
- `tokens`: required array of addresses.

Response shape:
- Same as GET variant.

Required by frontend:
- Same as GET variant.

Compatibility only:
- None.

## Classic Swap Quote API

### `GET /swap/v6.1/:chainId/quote`

Purpose:
- Indicative checkout preview only.
- Never treated as execution-locked.

Required query params:
- `src`: source token address or native sentinel.
- `dst`: destination token address or native sentinel.
- `amount`: source amount as integer string.

Optional supported query params for compatibility:
- `includeTokensInfo`: `true` or `false`
- `includeProtocols`: `true` or `false`
- `includeGas`: `true` or `false`

Initial request example:

```http
GET /swap/v6.1/11155111/quote?src=0xMockUsdc&dst=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE&amount=1000000
```

Response fields:
- `dstAmount`: required by frontend.
- `srcToken`: compatibility only, gated by `includeTokensInfo=true`.
- `dstToken`: compatibility only, gated by `includeTokensInfo=true`.
- `protocols`: compatibility only, gated by `includeProtocols=true`.
- `gas`: compatibility only, gated by `includeGas=true`.

Minimal response example:

```json
{
  "dstAmount": "523000000000000"
}
```

Expanded response example:

```json
{
  "dstAmount": "523000000000000",
  "srcToken": {
    "address": "0xMockUsdc",
    "symbol": "mUSDC",
    "name": "Mock USDC",
    "decimals": 6
  },
  "dstToken": {
    "address": "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    "symbol": "ETH",
    "name": "Ether",
    "decimals": 18
  },
  "gas": 150000,
  "protocols": [
    {
      "token": "0xMockUsdc",
      "hops": [
        {
          "part": 100,
          "dst": "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
          "fromTokenId": 0,
          "toTokenId": 1,
          "protocols": [
            {
              "name": "MOCK_FIXED_RATE",
              "part": 100
            }
          ]
        }
      ]
    }
  ]
}
```

Required by frontend:
- `dstAmount`

Compatibility only:
- `srcToken`
- `dstToken`
- `protocols`
- `gas`

Mock-mode rules:
- Quote is derived from the shared deterministic rate table.
- Fees are deterministic and baked into the computed `dstAmount`.
- If `src == dst`, return `400` for the initial version.
- If pair unsupported, return `400`.
- If liquidity unavailable, return `400`.

## Classic Swap Build API

### `GET /swap/v6.1/:chainId/swap`

Purpose:
- Build executable transaction payload for final confirmation.
- In production mode, this proxies 1inch swap construction.
- In mock mode, this builds calldata for the mock swap contract.

Required query params:
- `src`: source token address or native sentinel.
- `dst`: destination token address or native sentinel.
- `amount`: source amount as integer string.
- `from`: taker wallet address.
- `slippage`: numeric percent string.

Optional supported query params for compatibility:
- `receiver`
- `includeTokensInfo`
- `includeProtocols`
- `includeGas`
- `disableEstimate`
- `allowPartialFill`
- `usePermit2`

Initial request example:

```http
GET /swap/v6.1/11155111/swap?src=0xMockUsdc&dst=0xMockWbtc&amount=1000000&from=0xBuyer&slippage=1
```

Response fields:
- `dstAmount`: required by frontend.
- `tx`: required by frontend.
- `srcToken`: compatibility only, gated by `includeTokensInfo=true`.
- `dstToken`: compatibility only, gated by `includeTokensInfo=true`.
- `protocols`: compatibility only, gated by `includeProtocols=true`.
- `gas`: compatibility only, gated by `includeGas=true`.

Minimal response example:

```json
{
  "dstAmount": "29400",
  "tx": {
    "from": "0xBuyer",
    "to": "0xMockSwapContract",
    "data": "0xabcdef",
    "value": "0"
  }
}
```

Expanded response example:

```json
{
  "dstAmount": "29400",
  "tx": {
    "from": "0xBuyer",
    "to": "0xMockSwapContract",
    "data": "0xabcdef",
    "value": "0",
    "gas": 150000
  },
  "gas": 150000,
  "protocols": [
    {
      "token": "0xMockUsdc",
      "hops": [
        {
          "part": 100,
          "dst": "0xMockWbtc",
          "fromTokenId": 0,
          "toTokenId": 1,
          "protocols": [
            {
              "name": "MOCK_FIXED_RATE",
              "part": 100
            }
          ]
        }
      ]
    }
  ]
}
```

Required by frontend:
- `dstAmount`
- `tx.to`
- `tx.data`
- `tx.value`
- `tx.from`

Compatibility only:
- `tx.gas`
- top-level `gas`
- `srcToken`
- `dstToken`
- `protocols`

Mock-mode tx rules:
- `tx.to` is the mock swap contract.
- `tx.data` encodes the exact-input swap call.
- `tx.value` is the input ETH amount when `src` is native, otherwise `0`.
- `tx.from` echoes the `from` query param.
- `receiver` defaults to `from` if omitted.

Min-output protection:
- The backend computes `minReturnAmount` from `dstAmount` and `slippage`.
- That minimum must be encoded into the mock swap calldata or enforced by the mock swap contract call path.

Indicative versus final behavior:
- Frontend may show quote preview from `/quote`.
- Frontend must request `/swap` again at final confirmation time.

## Approve Allowance API

### `GET /swap/v6.1/:chainId/approve/allowance`

Purpose:
- Read ERC-20 allowance for the spender used by swap execution.

Required query params:
- `tokenAddress`
- `walletAddress`

Request example:

```http
GET /swap/v6.1/11155111/approve/allowance?tokenAddress=0xMockUsdc&walletAddress=0xBuyer
```

Response example:

```json
{
  "allowance": "0"
}
```

Required by frontend:
- `allowance`

Compatibility only:
- None.

Mock-mode rules:
- Spender is always the mock swap contract.
- Native ETH does not need allowance; initial backend may reject native-token allowance checks with `400`.

## Approve Transaction API

### `GET /swap/v6.1/:chainId/approve/transaction`

Purpose:
- Build ERC-20 approval transaction targeting the active spender.

Required query params:
- `tokenAddress`

Optional query params:
- `amount`

Request example:

```http
GET /swap/v6.1/11155111/approve/transaction?tokenAddress=0xMockUsdc&amount=1000000
```

Response example:

```json
{
  "to": "0xMockUsdc",
  "data": "0x095ea7b3000000000000000000000000...",
  "value": "0"
}
```

Required by frontend:
- `to`
- `data`
- `value`

Compatibility only:
- None.

Mock-mode rules:
- Approval spender is the mock swap contract.
- If `amount` omitted, backend may use max uint256 for standard tokens, but the initial preferred behavior is explicit exact-amount approval.
- For `mUSDT`, guidance must preserve zero-first semantics.

## mUSDT Zero-First Approval Rule

`mUSDT` intentionally mirrors legacy USDT approval behavior.

Meaning:
- Nonzero allowance to different nonzero allowance update reverts.

Required integration behavior:
- If current allowance is sufficient, do nothing.
- If current allowance is `0`, submit one approval to target amount.
- If current allowance is nonzero and insufficient, submit approval to `0`, wait for confirmation, then submit approval to target amount.

This logic is not encoded into the `/approve/transaction` endpoint itself.
It is an integration rule for the frontend or backend orchestration layer.

## Frontend Usage Contract

Listing grid:
- Uses Spot Price endpoints only.
- Must not request per-listing swap quotes.

Checkout preview:
- Uses `/swap/v6.1/:chainId/quote` for the selected listing only.

Checkout execution:
- Uses `/swap/v6.1/:chainId/swap` immediately before wallet submission.

Browser boundary:
- Frontend only calls this backend.
- Frontend never calls 1inch directly.

## Mock Determinism Rules

Required:
- Shared token registry across Spot Price, Quote, Swap, and approve helpers.
- Shared rate table across Spot Price and Quote/Swap.
- Deterministic fee application.

Forbidden by default:
- Random slippage.
- Random fees.
- Random quote jitter.

Suggested mock scenario knobs:
- `stable`
- `normal`
- `stressed`

These may alter configured fees or rates, but the selected scenario must still be deterministic.

## Open Follow-Up Items

Not required for initial contract freeze:
- Whether mock mode should support `receiver` immediately or only default to `from`.
- Whether native-token approval endpoints should reject with `400` or return a harmless zero-value stub.
- Whether to include top-level `gas` in every mock swap response or only when requested.
- Whether to expose a mock-only health or metadata endpoint outside the compatibility surface.

For the first implementation slice, treat only the fields marked `required by frontend` as mandatory.