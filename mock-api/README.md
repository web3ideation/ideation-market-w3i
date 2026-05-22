# Mock API

This folder will contain the backend service that exposes a frontend-compatible subset of the 1inch APIs.

Planned responsibilities:
- Mock `Spot Price API` responses for Sepolia using fixed rates
- Mock `Classic Swap v6.1` quote and swap responses for Sepolia
- Proxy the same endpoints to real 1inch in production mode
- Translate between 1inch native-token conventions and this repo's internal conventions when needed

Intended endpoint subset:
- `GET /price/v1.1/:chainId/:addresses`
- `POST /price/v1.1/:chainId`
- `GET /swap/v6.1/:chainId/quote`
- `GET /swap/v6.1/:chainId/swap`
- `GET /swap/v6.1/:chainId/approve/allowance`
- `GET /swap/v6.1/:chainId/approve/transaction`

Runtime baseline:
- Node.js 20+
- npm 10+

Deployment target options:
- local dev with `npm run dev`
- production deployment on an existing IONOS-managed Node/VPS environment
