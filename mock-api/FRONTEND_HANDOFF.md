# Frontend Handoff

This document is the frontend integration handoff for the separate FE repository.

## Goal

The frontend must integrate only with this backend service.
The browser must never call 1inch directly.

The frontend should switch only the backend base URL per environment.
Request shapes and frontend integration logic should stay the same across:
- production mode, where this backend proxies to 1inch
- mock mode, where this backend talks to the mock swap contract

## Backend endpoints the frontend should use

Spot Price:
- `GET /price/v1.1/:chainId/:addresses`
- `POST /price/v1.1/:chainId`

Classic Swap:
- `GET /swap/v6.1/:chainId/quote`
- `GET /swap/v6.1/:chainId/swap`
- `GET /swap/v6.1/:chainId/approve/allowance`
- `GET /swap/v6.1/:chainId/approve/transaction`

For exact request and response details, use `API_CONTRACT.md` as the source of truth.

## Required frontend integration changes

1. Replace any direct browser-side 1inch calls with calls to this backend base URL.

2. Listing grids must use Spot Price only:
- collect the unique currencies visible in the current listing set
- request Spot Price for those currencies plus the user's preferred display currency
- convert listing prices locally in the frontend
- do not request swap quotes for every visible listing

3. Checkout preview must use Quote only for the selected listing:
- call `GET /swap/v6.1/:chainId/quote`
- required params: `src`, `dst`, `amount`
- treat the result as indicative only

4. Final checkout execution must use Swap immediately before wallet submission:
- call `GET /swap/v6.1/:chainId/swap`
- required params: `src`, `dst`, `amount`, `from`, `slippage`
- use the returned `tx` object for wallet submission
- do not reuse an old quote as if it were execution-locked

5. ERC20 approval flow must use the backend helper endpoints:
- call `GET /swap/v6.1/:chainId/approve/allowance`
- if allowance is insufficient, call `GET /swap/v6.1/:chainId/approve/transaction`
- submit the returned transaction via the wallet

## mUSDT special rule

`mUSDT` follows legacy USDT approval semantics.

If current allowance is already sufficient:
- do nothing

If current allowance is `0`:
- submit one approval to the required amount

If current allowance is nonzero but insufficient:
- first approve `0`
- wait for confirmation
- then approve the required amount

This orchestration must exist in the frontend flow or in a higher-level integration layer.

## Required UX behavior

- Listing views use Spot Price only.
- Quote only the selected listing during checkout.
- Treat quote as indicative, not guaranteed.
- Re-request Swap immediately before final wallet submission.
- If the final swap result differs materially from the previewed quote, require user reconfirmation.

## Environment configuration the FE needs

The FE should expect one backend base URL per environment.

Any FE-side secrets or environment-specific configuration should be stored using
the same mechanism the current FE project already uses today.
Do not introduce a second secret-handling pattern just for this integration.

Examples:
- local mock backend base URL: `TBD`
- deployed mock backend base URL: `TBD`
- production backend base URL: `TBD`

These values should be provided once backend deployment is finalized.

## Notes

- Native ETH externally uses the sentinel `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`.
- The backend handles translation between that sentinel and internal native-token handling.
- The frontend should not add separate 1inch auth handling; production auth is injected server-side by this backend.
- The 1inch API key must remain server-side only and must never be exposed in browser code, public env files, or client bundles.