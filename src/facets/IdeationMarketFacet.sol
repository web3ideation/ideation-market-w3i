// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC165.sol";
import "../interfaces/IERC2981.sol";
import "../interfaces/IERC1155.sol";
import "../interfaces/IBuyerWhitelistFacet.sol";

error IdeationMarket__NotApprovedForMarketplace();
error IdeationMarket__AlreadyListed();
error IdeationMarket__SellerNotTokenOwner(uint128 listingId);
error IdeationMarket__NotAuthorizedOperator();
error IdeationMarket__ListingTermsChanged();
error IdeationMarket__FreeListingsNotSupported();
error IdeationMarket__PriceNotMet(uint128 listingId, uint256 price, uint256 value);
error IdeationMarket__SameBuyerAsSeller();
error IdeationMarket__NoSwapForSameToken();
error IdeationMarket__NotSupportedTokenStandard();
error IdeationMarket__NotListed();
error IdeationMarket__Reentrant();
error IdeationMarket__CollectionNotWhitelisted(address tokenAddress);
error IdeationMarket__BuyerNotWhitelisted(uint128 listingId, address buyer);
error IdeationMarket__InvalidNoSwapParameters();
error IdeationMarket__SellerInsufficientTokenBalance(uint256 required, uint256 available);
error IdeationMarket__RoyaltyFeeExceedsProceeds();
error IdeationMarket__NotAuthorizedToCancel();
error IdeationMarket__InsufficientSwapTokenBalance(uint256 required, uint256 available);
error IdeationMarket__WhitelistDisabled();
error IdeationMarket__WrongErc1155HolderParameter();
error IdeationMarket__WrongQuantityParameter();
error IdeationMarket__StillApproved();
error IdeationMarket__PartialBuyNotPossible();
error IdeationMarket__InvalidPurchaseQuantity();
error IdeationMarket__InvalidUnitPrice();
error IdeationMarket__CurrencyNotAllowed();
error IdeationMarket__WrongPaymentCurrency();
error IdeationMarket__EthTransferFailed(address receiver);
error IdeationMarket__ERC20TransferFailed(address token, address receiver);
error IdeationMarket__ContractPaused();

/// @title IdeationMarketFacet
/// @notice Core marketplace logic: create/update/cancel/purchase listings, optional buyer whitelists, swaps, partial buys, and fee/royalty accounting.
/// @dev Shared state via `LibAppStorage.AppStorage`. Key invariants & behaviors:
/// - Fee denominator is 100_000 (e.g., 1_000 = 1%). Each listing snapshots the fee into `Listing.feeRate`.
/// - Collection whitelist gates listing updates and purchases; de-whitelisting blocks buys and is cleaned via `cleanListing`.
/// - ERC-1155 vs ERC-721: `erc1155Quantity == 0` ⇒ ERC-721, `> 0` ⇒ ERC-1155. Partial buys only for ERC-1155 and require `price % quantity == 0`.
/// - Swaps: the buyer transfers a specified NFT to the seller during purchase; same-token swaps are disallowed.
/// - Royalties (ERC-2981) are deducted from seller proceeds and transferred directly to the royalty receiver during purchase.
///   If `royaltyReceiver == address(0)`, the marketplace skips royalties entirely (no deduction and no transfer).
/// - Payments are distributed atomically in order: marketplace owner (innovation fee) → royalty receiver (if any) → seller.
/// - ETH purchases require exact msg.value (no overpayment). ERC-20 purchases use buyer's approval for direct transfers to recipients (diamond never holds tokens).
/// - Reentrancy guard: single boolean `reentrancyLock` flip-flop in storage.
contract IdeationMarketFacet {
    /**
     * @notice Emitted when an item is listed on the marketplace.
     * @param listingId The listing ID.
     * @param tokenAddress The address of the NFT contract.
     * @param tokenId The token ID being listed.
     * @param price Listing price.
     * @param currency Payment currency (address(0) = ETH, otherwise ERC-20 token address).
     * @param seller The address of the seller.
     * @param desiredTokenAddress The desired NFT address for swaps (0 for non-swap listing).
     * @param desiredTokenId The desired token ID for swaps (only applicable for swap listing).
     * @param feeRate innovationFee rate at the time of listing in case it gets updated before selling.
     * @param erc1155Quantity Quantity (for ERC1155 tokens; must be 0 for ERC721).
     */
    event ListingCreated(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 erc1155Quantity,
        uint256 price,
        address currency,
        uint32 feeRate,
        address seller,
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    );

    event ListingPurchased(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 erc1155Quantity,
        bool partialBuy,
        uint256 price,
        address currency,
        uint32 feeRate,
        address seller,
        address buyer,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    );

    event ListingCanceled(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        address seller,
        address triggeredBy
    );

    event ListingUpdated(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 erc1155Quantity,
        uint256 price,
        address currency,
        uint32 feeRate,
        address seller,
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    );

    event InnovationFeeUpdated(uint32 previousFee, uint32 newFee);

    event ListingCanceledDueToInvalidListing(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        address seller,
        address triggeredBy
    );

    event InnovationFeePaid(
        uint128 indexed listingId, address indexed marketplaceOwner, address indexed currency, uint256 innovationFee
    );

    event RoyaltyPaid(
        uint128 indexed listingId, address indexed royaltyReceiver, address indexed currency, uint256 royaltyAmount
    );

    event SellerProceedsPaid(
        uint128 indexed listingId, address indexed seller, address indexed currency, uint256 sellerProceeds
    );

    event CollectionWhitelistRevokedCancelTriggered(uint128 indexed listingId, address indexed tokenAddress);

    ///////////////
    // Modifiers //
    ///////////////

    /// @notice Ensures the diamond is not paused.
    /// @dev Reverts with `IdeationMarket__ContractPaused` if the contract is paused.
    modifier whenNotPaused() {
        if (LibDiamond.diamondStorage().paused) revert IdeationMarket__ContractPaused();
        _;
    }

    /// @notice Ensures the listing exists (seller ≠ address(0)).
    /// @dev Reverts with `IdeationMarket__NotListed` if the listing does not exist.
    modifier listingExists(uint128 listingId) {
        if (LibAppStorage.appStorage().listings[listingId].seller == address(0)) revert IdeationMarket__NotListed();
        _;
    }

    /// @notice Prevents reentrancy attacks using a simple boolean lock.
    /// @dev Uses AppStorage.reentrancyLock to work across all facets in the diamond.
    modifier nonReentrant() {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.reentrancyLock) revert IdeationMarket__Reentrant();
        s.reentrancyLock = true;
        _;
        s.reentrancyLock = false;
    }

    ////////////////////
    // Main Functions //
    ////////////////////

    /// @notice Lists an NFT for sale (optional swap target, optional buyer whitelist, optional ERC-1155 partial buys).
    /// @param tokenAddress NFT contract address (ERC-721 or ERC-1155).
    /// @param tokenId Token id to list.
    /// @param erc1155Holder Required if `erc1155Quantity > 0`: the address whose ERC-1155 balance is being listed (can be caller or an owner who authorized caller).
    /// @param price Total listing price in wei. For ERC-1155 tokens with partial buys enabled, this price must be evenly divisible by `erc1155Quantity` to ensure consistent per-unit pricing.
    /// @param desiredTokenId Token id of the desired NFT if `desiredTokenAddress != 0`.
    /// @param desiredErc1155Quantity Desired quantity if the desired NFT is ERC-1155, else 0.
    /// @param erc1155Quantity Quantity for ERC-1155 listing; must be 0 for ERC-721 listing.
    /// @param buyerWhitelistEnabled If true, only pre-whitelisted buyers may purchase.
    /// @param partialBuyEnabled If true and ERC-1155, buyers may purchase a subset of units; requires `price % erc1155Quantity == 0` and swap must be disabled.
    /// @param allowedBuyers Optional initial whitelist addresses (only allowed if `buyerWhitelistEnabled == true`).
    /// @dev Reverts if: collection not whitelisted; wrong token standard vs quantity; caller not owner/authorized; insufficient ERC-1155 balance;
    /// partial-buy invalid (quantity ≤ 1 or price not divisible); ERC-721 already listed; invalid swap parameters; marketplace not approved.
    /// Snapshots `s.innovationFee` into the listing’s `feeRate`.
    function createListing(
        address tokenAddress,
        uint256 tokenId,
        address erc1155Holder,
        uint256 price,
        address currency,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 erc1155Quantity, // >0 for ERC1155, 0 for only ERC721
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address[] calldata allowedBuyers // whitelisted Buyers
    ) external whenNotPaused {
        AppStorage storage s = LibAppStorage.appStorage();

        // ============ Currency Validation ============
        // Ensure the currency is allowed (prevents listing in scam/malicious tokens)
        _enforceCurrencyAllowed(s, currency);

        // check if the Collection is Whitelisted
        _enforceCollectionWhitelisted(s, tokenAddress);

        // check if the user is an authorized Operator and set the seller Address to be the tokenHolders Address
        address seller = address(0);
        if (erc1155Quantity > 0) {
            // check that the quantity matches the token Type
            if (!IERC165(tokenAddress).supportsInterface(type(IERC1155).interfaceId)) {
                if (!IERC165(tokenAddress).supportsInterface(type(IERC721).interfaceId)) {
                    revert IdeationMarket__NotSupportedTokenStandard();
                } else {
                    revert IdeationMarket__WrongQuantityParameter();
                }
            }
            IERC1155 token = IERC1155(tokenAddress);
            // check if the user is authorized or the holder himself
            if (msg.sender != erc1155Holder && !token.isApprovedForAll(erc1155Holder, msg.sender)) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            // check that this 'erc1155Holder' is really the holder and that they hold enough token
            uint256 balance = token.balanceOf(erc1155Holder, tokenId);
            if (balance == 0) {
                revert IdeationMarket__WrongErc1155HolderParameter();
            }
            if (balance < erc1155Quantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(erc1155Quantity, balance);
            }
            seller = erc1155Holder;
        } else {
            // check that the quantity matches the token Type
            if (!IERC165(tokenAddress).supportsInterface(type(IERC721).interfaceId)) {
                if (!IERC165(tokenAddress).supportsInterface(type(IERC1155).interfaceId)) {
                    revert IdeationMarket__NotSupportedTokenStandard();
                } else {
                    revert IdeationMarket__WrongQuantityParameter();
                }
            }
            IERC721 token = IERC721(tokenAddress);
            address tokenHolder = token.ownerOf(tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != token.getApproved(tokenId)
                    && !token.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            seller = tokenHolder;
        }

        _validatePartialBuySetup(partialBuyEnabled, erc1155Quantity, price, desiredTokenAddress);

        // Prevent relisting an already-listed ERC721 NFT
        if (erc1155Quantity == 0 && s.activeListingIdByERC721[tokenAddress][tokenId] != 0) {
            revert IdeationMarket__AlreadyListed();
        }

        // check Swap parameters
        _validateSwapParameters(
            tokenAddress, tokenId, price, desiredTokenAddress, desiredTokenId, desiredErc1155Quantity
        );

        // ensure the MarketPlace has been Approved for transfer.
        if (erc1155Quantity > 0) {
            _requireERC1155Approval(tokenAddress, seller);
        } else {
            _requireERC721Approval(tokenAddress, tokenId);
        }

        s.listingIdCounter++;

        uint128 newListingId = s.listingIdCounter;

        s.listings[newListingId] = Listing({
            listingId: newListingId,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            erc1155Quantity: erc1155Quantity,
            price: price,
            feeRate: s.innovationFee,
            seller: seller,
            currency: currency,
            buyerWhitelistEnabled: buyerWhitelistEnabled,
            partialBuyEnabled: partialBuyEnabled,
            desiredTokenAddress: desiredTokenAddress,
            desiredTokenId: desiredTokenId,
            desiredErc1155Quantity: desiredErc1155Quantity
        });

        if (erc1155Quantity == 0) {
            s.activeListingIdByERC721[tokenAddress][tokenId] = newListingId;
        }

        _applyBuyerWhitelist(newListingId, buyerWhitelistEnabled, allowedBuyers);

        emit ListingCreated(
            s.listingIdCounter,
            tokenAddress,
            tokenId,
            erc1155Quantity,
            price,
            currency,
            s.innovationFee,
            seller,
            buyerWhitelistEnabled,
            partialBuyEnabled,
            desiredTokenAddress,
            desiredTokenId,
            desiredErc1155Quantity
        );
    }

    /// @notice Purchases a listing (optionally as a partial ERC-1155 buy and/or fulfilling a swap).
    /// @param listingId The target listing id.
    /// @param expectedPrice Caller's view of `listing.price` to guard against mid-tx updates.
    /// @param expectedCurrency Caller's view of `listing.currency` to guard against mid-tx updates (front-run protection).
    /// @param expectedErc1155Quantity Caller's view of `listing.erc1155Quantity` to guard against mid-tx updates.
    /// @param expectedDesiredTokenAddress Caller's view of `listing.desiredTokenAddress` to guard against mid-tx updates.
    /// @param expectedDesiredTokenId Caller's view of `listing.desiredTokenId` to guard against mid-tx updates.
    /// @param expectedDesiredErc1155Quantity Caller's view of `listing.desiredErc1155Quantity` to guard against mid-tx updates.
    /// @param erc1155PurchaseQuantity For ERC-1155: exact units to purchase (0 for ERC-721).
    /// @param desiredErc1155Holder If fulfilling an ERC-1155 swap, the holder whose balance/approval is checked for the desired token.
    /// @dev Reverts if: collection de-whitelisted; buyer not whitelisted (when enabled); terms mismatch (front-run protection);
    /// invalid purchase quantity; partial buy disallowed; payment amount incorrect (must be exact for ETH); seller equals buyer; seller no longer owns/approved;
    /// royalty exceeds proceeds; swap balance/approval insufficient.
    /// Accounting: fee = `price * feeRate / 100_000`, royalty (ERC-2981) deducted from seller proceeds.
    /// For ETH listings: requires exact msg.value (no overpayment allowed). For ERC-20 listings: uses buyer's approval to transfer directly to recipients.
    /// Payments distributed atomically after NFT transfer: marketplace owner (innovation fee) → royalty receiver (if any, from curated collections) → seller (proceeds).
    /// For swap listings, buyer's desired NFT is transferred to the seller before receiving the listed NFT.
    /// If a listing becomes unfulfillable (e.g., seller no longer owns/approved; swap terms cannot be met; collection de-whitelisted after listing),
    /// it is expected to be cleaned up via `cleanListing` (typically by an off-chain bot/indexer).
    function purchaseListing(
        uint128 listingId,
        uint256 expectedPrice,
        address expectedCurrency,
        uint256 expectedErc1155Quantity,
        address expectedDesiredTokenAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredErc1155Quantity,
        uint256 erc1155PurchaseQuantity,
        address desiredErc1155Holder
    ) external payable whenNotPaused nonReentrant listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[listingId];

        // Block purchase if the collection was de-whitelisted after listing
        _enforceCollectionWhitelisted(s, listedItem.tokenAddress);

        // BuyerWhitelist Check
        if (listedItem.buyerWhitelistEnabled) {
            if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {
                revert IdeationMarket__BuyerNotWhitelisted(listingId, msg.sender);
            }
        }

        // Check if Terms have changed in the meantime to guard against mid-tx updates (front-running protection)
        if (
            listedItem.price != expectedPrice || listedItem.currency != expectedCurrency
                || listedItem.desiredTokenAddress != expectedDesiredTokenAddress
                || listedItem.desiredTokenId != expectedDesiredTokenId
                || listedItem.desiredErc1155Quantity != expectedDesiredErc1155Quantity
                || listedItem.erc1155Quantity != expectedErc1155Quantity
        ) {
            revert IdeationMarket__ListingTermsChanged();
        }

        // Purchase‐quantity validations
        if (
            (listedItem.erc1155Quantity != 0 && erc1155PurchaseQuantity == 0)
                || (listedItem.erc1155Quantity == 0 && erc1155PurchaseQuantity != 0)
                || erc1155PurchaseQuantity > listedItem.erc1155Quantity
        ) {
            revert IdeationMarket__InvalidPurchaseQuantity();
        }
        if (!listedItem.partialBuyEnabled && erc1155PurchaseQuantity != listedItem.erc1155Quantity) {
            revert IdeationMarket__PartialBuyNotPossible();
        }

        // setting the purchasePrice based on partialBuy quantity
        uint256 purchasePrice = listedItem.price;

        if (erc1155PurchaseQuantity > 0 && erc1155PurchaseQuantity != listedItem.erc1155Quantity) {
            uint256 unitPrice = listedItem.price / listedItem.erc1155Quantity;
            purchasePrice = unitPrice * erc1155PurchaseQuantity;
        }

        // Payment Validation
        if (listedItem.currency == address(0)) {
            // ETH listing: require EXACT msg.value (no overpayment)
            if (msg.value != purchasePrice) {
                revert IdeationMarket__PriceNotMet(listedItem.listingId, purchasePrice, msg.value);
            }
        } else {
            // ERC-20 listing: msg.value must be 0
            // Tokens will be transferred directly from buyer to recipients later using buyer's approval
            if (msg.value > 0) {
                revert IdeationMarket__WrongPaymentCurrency();
            }
        }

        if (listedItem.desiredErc1155Quantity > 0 && desiredErc1155Holder == address(0)) {
            revert IdeationMarket__WrongErc1155HolderParameter();
        }

        if (msg.sender == listedItem.seller) {
            revert IdeationMarket__SameBuyerAsSeller();
        }

        // Check if the seller still owns the token and if the marketplace is still approved
        if (listedItem.erc1155Quantity > 0) {
            uint256 balance = IERC1155(listedItem.tokenAddress).balanceOf(listedItem.seller, listedItem.tokenId);
            if (balance < erc1155PurchaseQuantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(erc1155PurchaseQuantity, balance);
            }
            _requireERC1155Approval(listedItem.tokenAddress, listedItem.seller);
        } else {
            address ownerToken = IERC721(listedItem.tokenAddress).ownerOf(listedItem.tokenId);
            if (ownerToken != listedItem.seller) {
                revert IdeationMarket__SellerNotTokenOwner(listingId);
            }
            _requireERC721Approval(listedItem.tokenAddress, listedItem.tokenId);
        }

        // Calculate payment splits (will be distributed after NFT transfer)
        uint256 innovationFee = ((purchasePrice * listedItem.feeRate) / 100000);
        uint256 remainingProceeds = purchasePrice - innovationFee;

        address royaltyReceiver = address(0);
        uint256 royaltyAmount = 0;

        // Check for ERC2981 royalties
        if (IERC165(listedItem.tokenAddress).supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyReceiver, royaltyAmount) =
                IERC2981(listedItem.tokenAddress).royaltyInfo(listedItem.tokenId, purchasePrice);
            // Only deduct royalty if receiver is valid (not address(0)) and amount > 0
            if (royaltyReceiver != address(0) && royaltyAmount > 0) {
                if (remainingProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();
                remainingProceeds -= royaltyAmount;
            } else if (royaltyReceiver == address(0)) {
                // Skip royalty payment if receiver is address(0)
                royaltyAmount = 0;
            }
        }

        uint256 sellerProceeds = remainingProceeds;

        // in case it's a swap listing, send that desired token (the frontend approves the marketplace for that action beforehand)
        if (listedItem.desiredTokenAddress != address(0)) {
            if (listedItem.desiredErc1155Quantity > 0) {
                // For ERC1155: Check that buyer holds enough token.
                IERC1155 desiredToken = IERC1155(listedItem.desiredTokenAddress);
                uint256 swapBalance = desiredToken.balanceOf(desiredErc1155Holder, listedItem.desiredTokenId);
                if (swapBalance == 0) revert IdeationMarket__WrongErc1155HolderParameter();
                if (
                    msg.sender != desiredErc1155Holder
                        && !desiredToken.isApprovedForAll(desiredErc1155Holder, msg.sender)
                ) {
                    revert IdeationMarket__NotAuthorizedOperator();
                }
                if (swapBalance < listedItem.desiredErc1155Quantity) {
                    revert IdeationMarket__InsufficientSwapTokenBalance(listedItem.desiredErc1155Quantity, swapBalance);
                }

                // Check approval
                _requireERC1155Approval(listedItem.desiredTokenAddress, desiredErc1155Holder);

                // Perform the safe swap transfer buyer to seller.
                IERC1155(listedItem.desiredTokenAddress).safeTransferFrom(
                    desiredErc1155Holder,
                    listedItem.seller,
                    listedItem.desiredTokenId,
                    listedItem.desiredErc1155Quantity,
                    ""
                );
            } else {
                IERC721 desiredToken = IERC721(listedItem.desiredTokenAddress);
                address desiredOwner = desiredToken.ownerOf(listedItem.desiredTokenId);
                // For ERC721: Check ownership.
                if (
                    msg.sender != desiredOwner && msg.sender != desiredToken.getApproved(listedItem.desiredTokenId)
                        && !desiredToken.isApprovedForAll(desiredOwner, msg.sender)
                ) {
                    revert IdeationMarket__NotAuthorizedOperator();
                }

                // Check approval
                _requireERC721Approval(listedItem.desiredTokenAddress, listedItem.desiredTokenId);

                // Perform the safe swap transfer buyer to seller.
                desiredToken.safeTransferFrom(desiredOwner, listedItem.seller, listedItem.desiredTokenId);
            }
        }

        // Update or delete the listing
        bool partialBuy = false;
        if (erc1155PurchaseQuantity == listedItem.erc1155Quantity) {
            // fully bought → remove
            _deleteListingAndCleanup(
                s, listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.erc1155Quantity
            );
        } else {
            // partially bought → reduce remaining
            s.listings[listingId].erc1155Quantity -= erc1155PurchaseQuantity;
            s.listings[listingId].price -= purchasePrice;
            partialBuy = true;
        }

        // Transfer tokens based on the token standard.
        if (erc1155PurchaseQuantity > 0) {
            IERC1155(listedItem.tokenAddress).safeTransferFrom(
                listedItem.seller, msg.sender, listedItem.tokenId, erc1155PurchaseQuantity, ""
            );
        } else {
            IERC721(listedItem.tokenAddress).safeTransferFrom(listedItem.seller, msg.sender, listedItem.tokenId);
        }

        // Distribute payments atomically after NFT transfer (security: CEI pattern)
        _distributePayments(
            listedItem.currency,
            msg.sender,
            sellerProceeds,
            listedItem.seller,
            innovationFee,
            LibDiamond.contractOwner(),
            royaltyReceiver,
            royaltyAmount,
            listingId
        );

        emit ListingPurchased(
            listedItem.listingId,
            listedItem.tokenAddress,
            listedItem.tokenId,
            erc1155PurchaseQuantity,
            partialBuy,
            purchasePrice,
            listedItem.currency,
            listedItem.feeRate,
            listedItem.seller,
            msg.sender,
            listedItem.desiredTokenAddress,
            listedItem.desiredTokenId,
            listedItem.desiredErc1155Quantity
        );
    }

    /// @notice Cancels an existing listing.
    /// @dev Diamond owner may cancel any listing. Otherwise, only the seller or an authorized operator
    /// (ERC-721: token approval or approvalForAll; ERC-1155: approvalForAll) may cancel.
    /// Uses `try/catch` on external token calls to avoid bubbling token contract reverts.
    function cancelListing(uint128 listingId) public listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[listingId];

        // allow the diamondOwner to force cancel any listing
        address diamondOwner = LibDiamond.contractOwner();
        if (msg.sender == diamondOwner) {
            // delete Listing
            _deleteListingAndCleanup(
                s, listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.erc1155Quantity
            );
            emit ListingCanceled(listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.seller, msg.sender);
            return;
        }

        bool isAuthorized = false;
        // check if its an ERC721 or ERC1155 token contract
        if (listedItem.erc1155Quantity == 0) {
            IERC721 token = IERC721(listedItem.tokenAddress);

            // check if the caller is the item seller
            isAuthorized = (msg.sender == listedItem.seller);

            if (!isAuthorized) {
                // try check if the caller is approved for the sellers token by the token contract
                try token.getApproved(listedItem.tokenId) returns (address approvedAddress) {
                    if (approvedAddress == msg.sender) {
                        isAuthorized = true;
                    }
                } catch { /* ignore */ }
            }

            if (!isAuthorized) {
                // try check if the caller is approvedForAll the sellers tokens by the token contract
                try token.isApprovedForAll(listedItem.seller, msg.sender) returns (bool approved) {
                    if (approved) {
                        isAuthorized = true;
                    }
                } catch { /* ignore */ }
            }
        } else {
            // check if the caller is the item seller
            isAuthorized = (msg.sender == listedItem.seller);

            if (!isAuthorized) {
                try IERC1155(listedItem.tokenAddress).isApprovedForAll(listedItem.seller, msg.sender) returns (
                    bool approved
                ) {
                    if (approved) {
                        isAuthorized = true;
                    }
                } catch { /* ignore */ }
            }
        }

        if (isAuthorized) {
            // delete Listing
            _deleteListingAndCleanup(
                s, listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.erc1155Quantity
            );
            emit ListingCanceled(listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.seller, msg.sender);
            return;
        }
        revert IdeationMarket__NotAuthorizedToCancel();
    }

    /// @notice Updates listing terms (price, desired swap target, quantities, flags).
    /// @param listingId The listing id to update.
    /// @param newPrice New total price (for ERC-1155: total for `newErc1155Quantity`).
    /// @param newDesiredTokenAddress New desired NFT address for swap (0 for non-swap).
    /// @param newDesiredTokenId New desired token id for swap.
    /// @param newDesiredErc1155Quantity New desired ERC-1155 quantity for swap (0 for ERC-721 swap or non-swap).
    /// @param newErc1155Quantity New ERC-1155 quantity; must be 0 for ERC-721 listings.
    /// @param newBuyerWhitelistEnabled Whether whitelist gating is enabled.
    /// @param newPartialBuyEnabled Whether partial buys (ERC-1155 only) are enabled.
    /// @param newAllowedBuyers Optional addresses to add when enabling whitelist.
    /// @dev Reverts if token standard/quantity mismatch; caller not owner/authorized; insufficient ERC-1155 balance;
    /// marketplace not approved; collection de-whitelisted (auto-cancels and emits); invalid partial-buy setup
    /// (quantity ≤ 1 or price not divisible or swap enabled); invalid swap parameters.
    /// Updates `feeRate` to the current `innovationFee` snapshot.
    /// Auto-cancels the listing if the collection whitelist status has been revoked since the original listing was created.
    /// Emits `CollectionWhitelistRevokedCancelTriggered` when this occurs and exits early.
    function updateListing(
        uint128 listingId,
        uint256 newPrice,
        address newCurrency,
        address newDesiredTokenAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredErc1155Quantity,
        uint256 newErc1155Quantity,
        bool newBuyerWhitelistEnabled,
        bool newPartialBuyEnabled,
        address[] calldata newAllowedBuyers
    ) external whenNotPaused listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[listingId];

        // ensure the newQuantity is still valid according to the token Standard ( 0 for ERC721, >0 for ERC1155)
        if (newErc1155Quantity > 0) {
            if (listedItem.erc1155Quantity == 0) {
                revert IdeationMarket__WrongQuantityParameter();
            }
        } else {
            if (listedItem.erc1155Quantity > 0) {
                revert IdeationMarket__WrongQuantityParameter();
            }
        }

        // check if the user is an authorized operator and use interface check to ensure the MarketPlace is still Approved for transfer and seller holds enough token
        if (newErc1155Quantity > 0) {
            IERC1155 token = IERC1155(listedItem.tokenAddress);
            // check if the user is authorized
            if (msg.sender != listedItem.seller && !token.isApprovedForAll(listedItem.seller, msg.sender)) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            uint256 balance = token.balanceOf(listedItem.seller, listedItem.tokenId);
            if (balance < newErc1155Quantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(newErc1155Quantity, balance);
            }
            _requireERC1155Approval(listedItem.tokenAddress, listedItem.seller);
        } else {
            IERC721 token = IERC721(listedItem.tokenAddress);
            address tokenHolder = token.ownerOf(listedItem.tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != token.getApproved(listedItem.tokenId)
                    && !token.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            _requireERC721Approval(listedItem.tokenAddress, listedItem.tokenId);
        }

        //Validates collection whitelist status. If the collection was de-whitelisted after the original listing,
        // the listing is automatically canceled and `CollectionWhitelistRevokedCancelTriggered` is emitted.
        if (!s.whitelistedCollections[listedItem.tokenAddress]) {
            cancelListing(listingId);
            emit CollectionWhitelistRevokedCancelTriggered(listingId, listedItem.tokenAddress);
            return;
        }

        // Ensure the new currency is allowed
        _enforceCurrencyAllowed(s, newCurrency);

        _validatePartialBuySetup(newPartialBuyEnabled, newErc1155Quantity, newPrice, newDesiredTokenAddress);

        // check Swap parameters
        _validateSwapParameters(
            listedItem.tokenAddress,
            listedItem.tokenId,
            newPrice,
            newDesiredTokenAddress,
            newDesiredTokenId,
            newDesiredErc1155Quantity
        );

        listedItem.price = newPrice;
        listedItem.currency = newCurrency;
        listedItem.desiredTokenAddress = newDesiredTokenAddress;
        listedItem.desiredTokenId = newDesiredTokenId;
        listedItem.desiredErc1155Quantity = newDesiredErc1155Quantity;
        listedItem.erc1155Quantity = newErc1155Quantity;
        listedItem.feeRate = s.innovationFee;
        listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled;
        listedItem.partialBuyEnabled = newPartialBuyEnabled;

        _applyBuyerWhitelist(listingId, newBuyerWhitelistEnabled, newAllowedBuyers);

        emit ListingUpdated(
            listedItem.listingId,
            listedItem.tokenAddress,
            listedItem.tokenId,
            newErc1155Quantity,
            newPrice,
            newCurrency,
            listedItem.feeRate,
            listedItem.seller,
            newBuyerWhitelistEnabled,
            newPartialBuyEnabled,
            newDesiredTokenAddress,
            newDesiredTokenId,
            newDesiredErc1155Quantity
        );
    }

    /// @notice Updates the marketplace fee rate  (e.g., 1_000 for 1% with a denominator of 100_000).
    /// @dev Owner-only. Existing listings are unaffected (they keep their stored `feeRate`).
    /// Emits `InnovationFeeUpdated`.
    function setInnovationFee(uint32 newFee) external {
        LibDiamond.enforceIsContractOwner();
        AppStorage storage s = LibAppStorage.appStorage();
        uint32 previousFee = s.innovationFee;
        s.innovationFee = newFee;
        emit InnovationFeeUpdated(previousFee, newFee);
    }

    /// @notice Validates and removes an invalid listing (ownership/approval/whitelist checks).
    /// @dev Intended for off-chain maintenance bots but callable by anyone. For ERC-721/1155:
    /// verifies owner/balance and marketplace approval (using `try/catch` to handle token contract reverts).
    /// Uses `do-while(false)` pattern as a structured alternative to goto - allows early exit via `break`
    /// statements without nested if-else blocks when any validation fails.
    /// If invalid, deletes the listing and emits `ListingCanceledDueToInvalidListing`; otherwise reverts `IdeationMarket__StillApproved`.
    function cleanListing(uint128 listingId) external listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[listingId];

        bool invalid = false;

        // Using do-while(false) loop as a control flow structure - allows clean early exit via 'break'
        // instead of deeply nested if-else conditions when validation checks fail
        do {
            // check if the Collection is still Whitelisted
            if (s.whitelistedCollections[listedItem.tokenAddress]) {
                // check ownership and approval depending on token type
                if (listedItem.erc1155Quantity > 0) {
                    IERC1155 token = IERC1155(listedItem.tokenAddress);

                    // balanceOf may revert on invalid tokens → delete
                    try token.balanceOf(listedItem.seller, listedItem.tokenId) returns (uint256 balance) {
                        if (balance < listedItem.erc1155Quantity) {
                            invalid = true;
                            break;
                        }
                    } catch {
                        invalid = true;
                        break;
                    }

                    // isApprovedForAll may revert → delete
                    try token.isApprovedForAll(listedItem.seller, address(this)) returns (bool approved) {
                        if (!approved) {
                            invalid = true;
                            break;
                        }
                    } catch {
                        invalid = true;
                        break;
                    }
                } else {
                    IERC721 token = IERC721(listedItem.tokenAddress);

                    // ownerOf may revert for burned/nonexistent → delete
                    try token.ownerOf(listedItem.tokenId) returns (address currOwner) {
                        if (currOwner != listedItem.seller) {
                            invalid = true;
                            break;
                        }
                    } catch {
                        invalid = true;
                        break;
                    }

                    // getApproved may revert → delete
                    try token.getApproved(listedItem.tokenId) returns (address approved) {
                        if (approved != address(this)) {
                            // isApprovedForAll may also revert → delete
                            try token.isApprovedForAll(listedItem.seller, address(this)) returns (bool approvedForAll) {
                                if (!approvedForAll) {
                                    invalid = true;
                                    break;
                                }
                            } catch {
                                invalid = true;
                                break;
                            }
                        }
                    } catch {
                        invalid = true;
                        break;
                    }
                }
            } else {
                invalid = true;
                break;
            }
        } while (false);

        if (invalid) {
            _deleteListingAndCleanup(
                s, listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.erc1155Quantity
            );
            emit ListingCanceledDueToInvalidListing(
                listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.seller, msg.sender
            );
            return;
        }

        revert IdeationMarket__StillApproved();
    }

    //////////////////////
    // Helper Functions //
    //////////////////////

    /// @notice Reverts if `currency` is not allowed.
    /// @dev Centralizes the `allowedCurrencies` guard.
    function _enforceCurrencyAllowed(AppStorage storage s, address currency) private view {
        if (!s.allowedCurrencies[currency]) {
            revert IdeationMarket__CurrencyNotAllowed();
        }
    }

    /// @notice Reverts if `tokenAddress` is not on the collection whitelist.
    /// @dev Centralizes the collection whitelist guard.
    function _enforceCollectionWhitelisted(AppStorage storage s, address tokenAddress) private view {
        if (!s.whitelistedCollections[tokenAddress]) {
            revert IdeationMarket__CollectionNotWhitelisted(tokenAddress);
        }
    }

    /// @notice Validates partial-buy configuration.
    /// @dev Only meaningful for ERC-1155 listings. Partial buys are forbidden for swap listings.
    function _validatePartialBuySetup(
        bool partialBuyEnabled,
        uint256 erc1155Quantity,
        uint256 price,
        address desiredTokenAddress
    ) private pure {
        if (!partialBuyEnabled) return;

        if (erc1155Quantity <= 1) {
            revert IdeationMarket__PartialBuyNotPossible();
        }

        if (price % erc1155Quantity != 0) {
            revert IdeationMarket__InvalidUnitPrice();
        }

        if (desiredTokenAddress != address(0)) {
            revert IdeationMarket__PartialBuyNotPossible();
        }
    }

    /// @notice Applies buyer-whitelist configuration for a listing.
    /// @dev If enabled and addresses are provided, delegates to `BuyerWhitelistFacet` on this diamond.
    function _applyBuyerWhitelist(uint128 listingId, bool buyerWhitelistEnabled, address[] calldata allowedBuyers)
        private
    {
        if (buyerWhitelistEnabled) {
            if (allowedBuyers.length > 0) {
                IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId, allowedBuyers);
            }
        } else {
            if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();
        }
    }

    /// @notice Requires this diamond to be approved to transfer the ERC-721 token.
    /// @dev Accepts either token-level approval (`getApproved`) or operator approval (`isApprovedForAll`).
    /// Reverts `IdeationMarket__NotApprovedForMarketplace` if neither is set.
    function _requireERC721Approval(address tokenAddress, uint256 tokenId) internal view {
        IERC721 token = IERC721(tokenAddress);
        if (
            !(
                token.getApproved(tokenId) == address(this)
                    || token.isApprovedForAll(token.ownerOf(tokenId), address(this))
            )
        ) {
            revert IdeationMarket__NotApprovedForMarketplace();
        }
    }

    /// @notice Requires this diamond to be approved as operator for an ERC-1155 holder.
    /// @dev Checks `isApprovedForAll(tokenOwner, address(this))`
    /// Reverts on failure.
    function _requireERC1155Approval(address tokenAddress, address tokenOwner) internal view {
        if (!IERC1155(tokenAddress).isApprovedForAll(tokenOwner, address(this))) {
            revert IdeationMarket__NotApprovedForMarketplace();
        }
    }

    /// @notice Validates swap configuration for a listing.
    /// @dev Disallows swapping for the same token (same contract + id).
    /// Non-swap: `desiredTokenAddress == 0`, `desiredTokenId == 0`, `desiredErc1155Quantity == 0`, and `price > 0`.
    /// Swap ERC-1155: `desiredErc1155Quantity > 0` and desired contract must support ERC-1155.
    /// Swap ERC-721: `desiredErc1155Quantity == 0` and desired contract must support ERC-721.
    function _validateSwapParameters(
        address tokenAddress,
        uint256 tokenId,
        uint256 price,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    ) private view {
        if (desiredTokenAddress == address(0)) {
            if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (desiredErc1155Quantity != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (price == 0) revert IdeationMarket__FreeListingsNotSupported();
        } else {
            if (desiredErc1155Quantity > 0) {
                if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC1155).interfaceId)) {
                    revert IdeationMarket__NotSupportedTokenStandard();
                }
            }
            if (desiredErc1155Quantity == 0) {
                if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC721).interfaceId)) {
                    revert IdeationMarket__NotSupportedTokenStandard();
                }
            }
            if (tokenAddress == desiredTokenAddress && tokenId == desiredTokenId) {
                revert IdeationMarket__NoSwapForSameToken();
            }
        }
    }

    /// @notice Deletes a listing and clears the ERC-721 active listing id, if applicable.
    function _deleteListingAndCleanup(
        AppStorage storage s,
        uint128 listingId,
        address tokenAddress,
        uint256 tokenId,
        uint256 erc1155Quantity
    ) internal {
        delete s.listings[listingId];

        if (erc1155Quantity == 0) {
            delete s.activeListingIdByERC721[tokenAddress][tokenId];
        }
    }

    /// @notice Distributes payment directly from buyer to all recipients atomically.
    /// @dev Called AFTER NFT transfer to prevent reentrancy. For ETH: forwards from contract balance.
    /// For ERC-20: uses buyer's approval to transfer directly (contract never holds tokens).
    /// Payment order: marketplace owner (most trusted) → royalty receiver → seller (least trusted).
    /// @param currency Payment currency (address(0) = ETH, otherwise ERC-20).
    /// @param buyer Address of the buyer (for ERC-20 transferFrom source).
    /// @param sellerProceeds Amount to send to seller.
    /// @param seller Seller address.
    /// @param innovationFee Marketplace fee amount.
    /// @param marketplaceOwner Marketplace owner address.
    /// @param royaltyReceiver Royalty recipient (address(0) if no royalty).
    /// @param royaltyAmount Royalty amount (0 if no royalty).
    /// @param listingId For RoyaltyPaid event emission.

    function _distributePayments(
        address currency,
        address buyer,
        uint256 sellerProceeds,
        address seller,
        uint256 innovationFee,
        address marketplaceOwner,
        address royaltyReceiver,
        uint256 royaltyAmount,
        uint128 listingId
    ) private {
        if (currency == address(0)) {
            // ===== NATIVE ETH DISTRIBUTION =====
            // Diamond received ETH via msg.value, now forward it

            // 1. Pay marketplace owner FIRST (most trusted)
            (bool successFee,) = payable(marketplaceOwner).call{value: innovationFee}("");
            if (!successFee) revert IdeationMarket__EthTransferFailed(marketplaceOwner);
            emit InnovationFeePaid(listingId, marketplaceOwner, currency, innovationFee);

            // 2. Pay royalty receiver SECOND
            if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
                (bool successRoyalty,) = payable(royaltyReceiver).call{value: royaltyAmount}("");
                if (!successRoyalty) revert IdeationMarket__EthTransferFailed(royaltyReceiver);
                emit RoyaltyPaid(listingId, royaltyReceiver, currency, royaltyAmount);
            }

            // 3. Pay seller LAST (least trusted)
            (bool successSeller,) = payable(seller).call{value: sellerProceeds}("");
            if (!successSeller) revert IdeationMarket__EthTransferFailed(seller);
            emit SellerProceedsPaid(listingId, seller, currency, sellerProceeds);
        } else {
            // ===== ERC-20 DISTRIBUTION =====
            // Use buyer's approval to transfer directly: buyer → recipients
            // Diamond NEVER holds the tokens

            // 1. Pay marketplace owner FIRST (most trusted)
            _safeTransferFrom(currency, buyer, marketplaceOwner, innovationFee);
            emit InnovationFeePaid(listingId, marketplaceOwner, currency, innovationFee);

            // 2. Pay royalty receiver SECOND
            if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
                _safeTransferFrom(currency, buyer, royaltyReceiver, royaltyAmount);
                emit RoyaltyPaid(listingId, royaltyReceiver, currency, royaltyAmount);
            }

            // 3. Pay seller LAST (least trusted)
            _safeTransferFrom(currency, buyer, seller, sellerProceeds);
            emit SellerProceedsPaid(listingId, seller, currency, sellerProceeds);
        }
    }

    /// @notice SafeERC20-style transferFrom that handles non-standard tokens.
    /// @dev Handles tokens like USDT that don't return bool, and tokens that return false on failure.
    /// Uses low-level call to avoid ABI decoding issues with non-compliant ERC-20 tokens.
    /// @param token ERC-20 token address.
    /// @param from Address to transfer from.
    /// @param to Address to transfer to.
    /// @param amount Amount to transfer.
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        // Build the calldata for ERC20.transferFrom(address,address,uint256)
        // Function selector: bytes4(keccak256("transferFrom(address,address,uint256)")) = 0x23b872dd
        bytes memory data = abi.encodeWithSelector(0x23b872dd, from, to, amount);

        // Call the token contract
        (bool success, bytes memory returndata) = token.call(data);

        // Check for success:
        // 1. Call must not revert
        // 2. If returndata exists, it must decode to true (handles tokens that return bool)
        // 3. If no returndata, assume success (handles USDT, XAUt that don't return anything)
        if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            revert IdeationMarket__ERC20TransferFailed(token, to);
        }
    }

    // View / Getter functions are implemented in GetterFacet.sol to maintain separation of concerns in the diamond pattern.
}
