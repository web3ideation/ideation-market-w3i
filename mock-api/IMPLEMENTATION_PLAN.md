# Mock API Implementation Plan

## Goal
Build a backend that presents the same frontend-facing HTTP surface in both environments:
- production: proxy selected endpoints to 1inch
- sepolia mock: answer selected endpoints from fixed mock rates and build swap txs for the mock swap contract

The frontend should only switch backend base URL, not request shape or integration logic.

Important boundary:
- Production 1inch compatibility is an HTTP API compatibility goal, not an onchain contract ABI compatibility goal.
- The frontend must talk only to this backend service, never directly to 1inch from the browser.
- In production, this backend proxies to real 1inch with server-side auth.
- In Sepolia mock mode, this backend returns the same request/response shapes but targets the mock swap contract.

## Supported API subset
### Spot Price
- `GET /price/v1.1/:chainId/:addresses`
- `POST /price/v1.1/:chainId`

### Classic Swap v6.1
- `GET /swap/v6.1/:chainId/quote`
- `GET /swap/v6.1/:chainId/swap`
- `GET /swap/v6.1/:chainId/approve/allowance`
- `GET /swap/v6.1/:chainId/approve/transaction`

## External compatibility rules
- Use current Classic field names: `src`, `dst`, `amount`, `from`, `slippage`
- Return current response fields such as `dstAmount` and `tx`
- Represent native ETH externally as `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`
- Keep frontend request and response handling identical across prod and mock
- Keep the supported subset intentionally narrow; do not attempt full 1inch parity unless the frontend actually needs more fields/endpoints

## Token universe
Initial mock support covers exactly:
- ETH (native)
- mERC20
- mUSDC
- mWBTC
- mEURS
- mUSDT

The deployed mock ERC20s already exist in this repo and are currently deployed via `script/DeployMocksAndMint.s.sol`.
The fixed-rate mock swap is deployed separately via `script/DeployMockSwap.s.sol` using those token addresses.

## Onchain mock scope
Build one simple fixed-rate swap contract for:
- ETH
- mERC20
- mUSDC
- mWBTC
- mEURS
- mUSDT

Contract responsibilities:
- exact-input quote
- exact-input swap
- ERC20 -> ERC20
- ETH -> ERC20
- ERC20 -> ETH
- contract-prefunded liquidity only
- deterministic fee application

Non-goals for the initial contract:
- pathfinding
- protocol splitting
- dynamic liquidity discovery
- exact-output routing
- mimicking 1inch router internals

## Backend runtime scope
Mock mode responsibilities:
- map token addresses to configured assets
- answer spot price from fixed rates
- answer quote from fixed rates
- build swap transaction payload targeting the mock swap contract
- expose approve helper endpoints with the mock swap contract as spender

Mock mode design rules:
- Use one shared token registry for Spot Price, Quote, Swap, and approval helpers.
- Use one shared rate table for Spot Price and Quote so display prices and executable quotes stay aligned.
- Translate between the external 1inch ETH sentinel and the repo's internal native ETH conventions offchain.
- Keep behavior deterministic by default.

Production mode responsibilities:
- proxy the same routes to real 1inch
- inject auth server-side
- keep the same external response contract for the frontend

Production mode design rules:
- Never expose the 1inch API key in browser-side code.
- Expect quote results to be indicative only; there is no lock between quote and swap.
- Requote immediately before swap construction when the user confirms a buy.

## Price display strategy
The listing grid must not use swap quotes for all visible items.

Required flow for listing display:
- collect the unique listing currencies currently visible
- fetch Spot Price for those currencies plus the user's preferred currency
- convert all listing prices locally in the frontend

Reason:
- swap quoting 50 visible listings is the wrong abstraction
- it creates unnecessary load and will hit 1inch free-tier rate limits quickly
- Spot Price is the right surface for display pricing

Practical rule:
- listing display uses Spot Price only
- selected-item checkout uses Classic Quote and Classic Swap only

## Quote semantics and checkout behavior
Classic quote is indicative only and does not lock execution.

Implications:
- a quote does not reserve liquidity
- a quote does not lock price
- between quote and swap, the market can move

Required UX behavior:
- use quote for preview only
- when the user confirms, build a fresh swap immediately
- if the fresh result differs materially from the shown preview, prompt the user to reconfirm
- rely on slippage / minimum-output protection so bad fills revert rather than silently executing at an unacceptable outcome

## Exact-output limitation and recommended handling
1inch Classic does not provide the exact-output checkout shape we wanted.

Initial implementation model:
- use exact-input quote and swap only
- estimate required input for preview
- on final buy, refresh the quote and construct swap from a bounded max input / protected min output flow

Important note:
- this protects the user from overspending input beyond the submitted source amount
- it does not by itself provide a perfect exact-output purchase experience

Recommended follow-up architecture:
- introduce a wrapper / settlement contract in a later phase
- wrapper contract should enforce max spend, minimum received listing currency, and refund logic for leftovers or unused amounts

This wrapper contract is the most realistic path to an exact-purchase UX if exact-output routing is unavailable.

## Fee modeling
Mock mode should include fees, but fees must be deterministic rather than randomized.

Do not do by default:
- realtime-randomized fees
- random slippage noise
- non-deterministic quote changes

Reason:
- random behavior makes the mock harder to debug
- random behavior causes flaky tests
- random behavior obscures whether failures come from the integration or the mock

Required fee approach:
- store fees in basis points
- configure fees per pair, per token class, or per scenario
- apply the same fee logic consistently in Spot Price-derived execution views and Quote/Swap logic where relevant

Suggested scenarios:
- `stable`
- `normal`
- `stressed`

Example fee direction:
- stable/stable pairs: low bps
- ETH/stable pairs: medium bps
- WBTC pairs: slightly higher bps

## Approval behavior note for mUSDT
`mUSDT` intentionally behaves like old USDT and enforces zero-first approval changes.

Meaning:
- changing allowance from one nonzero value to another nonzero value directly will fail
- the allowance must first be set to `0`
- then it can be set to the new nonzero value

Required helper logic:
- if allowance is already sufficient, do nothing
- if allowance is `0`, approve the required amount
- if allowance is nonzero but insufficient, first approve `0`, wait for confirmation, then approve the required amount

## Step-by-step execution
1. [x] Freeze API contract
- Write exact request params and response fields for each supported endpoint.
- Do not build beyond the subset the frontend actually uses.
- Explicitly document which response fields are required by the frontend versus optional compatibility fields.

2. [x] Implement mock swap contract
- Add fixed-rate config.
- Add quote and swap methods.
- Handle ETH sentinel translation offchain, not in the contract.
- Add deterministic fee configuration.

3. [x] Add Foundry tests
- decimals handling
- min return checks
- unsupported pairs
- liquidity shortfalls
- ETH in/out flows
- fee application correctness
- zero-first approval integration guidance for mUSDT flows where relevant

4. [x] Add deploy scripts
- keep `script/DeployMocksAndMint.s.sol` scoped to mock token deployment and recipient minting
- use `script/DeployMockSwap.s.sol` to deploy the mock swap contract
- optionally seed token and ETH liquidity in the swap deploy step
- print backend-ready env values from the swap deploy step

5. [x] Initialize backend app
- Node + TypeScript or plain Node
- env loading
- health endpoint
- token registry and rate table config
- current local runtime baseline is Node.js 20.10.0 and npm 10.2.3, which is compatible with this backend work

6. [x] Implement Spot Price mock
- support both GET and POST variants if needed
- return prices from the same rate table used by swap logic
- support the listing-grid conversion flow efficiently for many listings / few unique currencies

7. [x] Implement Classic Quote mock
- accept `src`, `dst`, `amount`
- return deterministic `dstAmount`
- include only the fields the frontend needs first
- treat the result as indicative only, not execution-locked

8. [x] Implement Classic Swap mock
- accept `src`, `dst`, `amount`, `from`, `slippage`
- build tx payload to call the mock swap contract
- set `value` correctly for ETH input
- make sure max input and minimum acceptable output protections are represented consistently

9. [x] Implement approve helpers
- spender must be the mock swap contract in mock mode
- handle zero-first approval flow for mUSDT in frontend/backend guidance

10. [ ] Wire frontend to backend only
- listing prices from Spot Price endpoint
- buy execution from Quote and Swap endpoints
- never call 1inch directly from the browser
- Blocked in this workspace because the frontend lives in a separate repo owned by the FE.
- This step ends with a concrete handoff description to the FE rather than a code change in this repo.
- Current handoff document: `mock-api/FRONTEND_HANDOFF.md`.
- [x] FE handoff draft created in `mock-api/FRONTEND_HANDOFF.md`.
- [ ] Actual frontend rewiring still has to happen in the separate FE repository.

11. [x] Add production proxy mode
- same endpoints
- same backend base path
- real 1inch behind the service
- requote on final confirmation before returning final swap construction
 - Basic pass-through is implemented; live upstream validation still requires a real 1inch API key.

12. [ ] Deploy backend
- [x] local first
- [ ] production on the existing IONOS-managed environment used by the team
- Local validation is complete.
- Local `.env`-based startup is now implemented and documented in `mock-api/README.md`.
- The FE confirmed the current IONOS deployment shape is Docker.
- Docker deployment assets now exist in `mock-api/Dockerfile` and `mock-api/.dockerignore`.
- Production rollout in IONOS is no longer blocked on runtime-shape uncertainty; it is now blocked on actual container deployment, final backend base URL, and production secrets.
- Live production proxy validation against real 1inch still requires a real API key and final deployment target details.

13. [ ] Wrapper-contract phase (follow-up, not required for first delivery)
- design a wrapper / settlement contract for max-spend plus refund behavior
- use it to improve the exact-purchase UX when exact-output routing is unavailable

## UX rules
- For listing grids: use Spot Price API and local conversion only
- For buy flow: quote only the selected listing
- Treat quote as indicative, not guaranteed
- Enforce user protection with swap slippage and marketplace max-spend logic
- Do not quote all visible listings through the swap endpoint
- If final requote differs materially from the preview, require reconfirmation

## Deployment notes
Local machine status already verified:
- Node.js `v20.10.0`
- npm `10.2.3`
- Docker installed (`24.0.7`) but optional for the initial backend work
- git installed

Recommended production direction:
- deploy this backend into the team's existing IONOS-managed environment rather than introducing a separate hosting platform unless the team explicitly wants that
- current confirmed target shape: Docker on the existing IONOS-managed environment

## Notes for future agent sessions
- Start from this file and execute one numbered step at a time.
- After each step, validate before widening scope.
- Do not expand to unsupported 1inch endpoints unless the frontend needs them.
- Treat this file as the current source of truth for agreed architecture decisions.

## Final coordination items
- The frontend integration cannot be completed in this repo because the frontend lives in a separate repository.
- Before closing this implementation phase, send the FE a handoff description for the frontend changes that are required.
- The current draft handoff is in `mock-api/FRONTEND_HANDOFF.md`.
- That handoff should state that the frontend must call this backend only and must never call 1inch directly from the browser.
- That handoff should state that listing grids must use the Spot Price endpoints only, with local conversion for visible listings.
- That handoff should state that checkout preview must use `GET /swap/v6.1/:chainId/quote` only for the selected listing.
- That handoff should state that final execution must call `GET /swap/v6.1/:chainId/swap` immediately before wallet submission.
- That handoff should state that ERC20 approval flow must use the backend allowance and approve helper endpoints, with zero-first handling for `mUSDT` when allowance is nonzero but insufficient.
- That handoff should include the backend base URL per environment once deployment details are finalized.
- IONOS uses a Docker-based deployment path according to the FE.
- There are no further backend code changes required in this repo before sending the FE the current handoff.
- The remaining items before full FE integration are finalized backend base URLs, actual container rollout on IONOS, the real 1inch API key, and the frontend code changes in the separate FE repo.
