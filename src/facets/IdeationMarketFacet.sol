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
error IdeationMarket__NoProceeds();
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
error IdeationMarket__TransferFailed();
error IdeationMarket__InsufficientSwapTokenBalance(uint256 required, uint256 available);
error IdeationMarket__WhitelistDisabled();
error IdeationMarket__WrongErc1155HolderParameter();
error IdeationMarket__WrongQuantityParameter();
error IdeationMarket__StillApproved();
error IdeationMarket__PartialBuyNotPossible();
error IdeationMarket__InvalidPurchaseQuantity();
error IdeationMarket__InvalidUnitPrice();

/// @title IdeationMarketFacet
/// @notice Core marketplace logic: create/update/cancel/purchase listings, optional buyer whitelists, swaps, partial buys, and fee/royalty accounting.
/// @dev Shared state via `LibAppStorage.AppStorage`. Key invariants & behaviors:
/// - Fee denominator is 100_000 (e.g., 1_000 = 1%). Each listing snapshots the fee into `Listing.feeRate`.
/// - Collection whitelist gates listing updates and purchases; de-whitelisting blocks buys and is cleaned via `cleanListing`.
/// - ERC-1155 vs ERC-721: `erc1155Quantity == 0` ⇒ ERC-721, `> 0` ⇒ ERC-1155. Partial buys only for ERC-1155 and require `price % quantity == 0`.
/// - Swaps: the buyer transfers a specified NFT to the seller during purchase; same-token swaps are disallowed.
/// - Royalties (ERC-2981) are deducted from the seller’s proceeds and credited to the royalty receiver in `proceeds`.
/// - Excess ETH sent in a purchase is credited to the buyer’s `proceeds` (withdrawn via `withdrawProceeds`), not auto-refunded inline.
/// - Reentrancy guard: single boolean `reentrancyLock` flip-flop in storage.
contract IdeationMarketFacet {
    /**
     * @notice Emitted when an item is listed on the marketplace.
     * @param listingId The listing ID.
     * @param tokenAddress The address of the NFT contract.
     * @param tokenId The token ID being listed.
     * @param price Listing price.
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
        uint32 feeRate,
        address seller,
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    );

    event ProceedsWithdrawn(address indexed withdrawer, uint256 amount);

    event InnovationFeeUpdated(uint32 previousFee, uint32 newFee);

    event ListingCanceledDueToInvalidListing(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        address seller,
        address triggeredBy
    );

    event RoyaltyPaid(
        uint128 indexed listingId,
        address indexed royaltyReceiver,
        address indexed tokenAddress,
        uint256 tokenId,
        uint256 royaltyAmount
    );

    event CollectionWhitelistRevokedCancelTriggered(uint128 indexed listingId, address indexed tokenAddress);

    ///////////////
    // Modifiers //
    ///////////////

    /// @notice Ensures the listing exists (seller ≠ address(0)).
    /// @dev Reverts with `IdeationMarket__NotListed` if the listing does not exist.
    modifier listingExists(uint128 listingId) {
        if (LibAppStorage.appStorage().listings[listingId].seller == address(0)) revert IdeationMarket__NotListed();
        _;
    }

    /// @notice Simple non-reentrancy guard.
    /// @dev Reverts with `IdeationMarket__Reentrant` when re-entered in guarded functions.
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
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 erc1155Quantity, // >0 for ERC1155, 0 for only ERC721
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address[] calldata allowedBuyers // whitelisted Buyers
    ) external {
        AppStorage storage s = LibAppStorage.appStorage();

        // check if the Collection is Whitelisted
        if (!s.whitelistedCollections[tokenAddress]) {
            revert IdeationMarket__CollectionNotWhitelisted(tokenAddress);
        }

        // check if the user is an authorized Operator and set the seller Address
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

        // check validity of partialBuyEnabled Flag
        if (erc1155Quantity <= 1 && partialBuyEnabled) {
            revert IdeationMarket__PartialBuyNotPossible();
        }

        if (partialBuyEnabled) {
            // price must be divisible by quantity
            if (price % erc1155Quantity != 0) {
                revert IdeationMarket__InvalidUnitPrice();
            }
            // forbid partialbuys if its a swap listing
            if (desiredTokenAddress != address(0)) {
                revert IdeationMarket__PartialBuyNotPossible();
            }
        }

        // Prevent relisting an already-listed ERC721 NFT
        if (erc1155Quantity == 0 && s.tokenToListingIds[tokenAddress][tokenId].length > 0) {
            revert IdeationMarket__AlreadyListed();
        }

        validateSwapParameters(
            tokenAddress, tokenId, price, desiredTokenAddress, desiredTokenId, desiredErc1155Quantity
        );

        // ensure the MarketPlace has been Approved for transfer.
        if (erc1155Quantity > 0) {
            requireERC1155Approval(tokenAddress, seller);
        } else {
            requireERC721Approval(tokenAddress, tokenId);
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
            buyerWhitelistEnabled: buyerWhitelistEnabled,
            partialBuyEnabled: partialBuyEnabled,
            desiredTokenAddress: desiredTokenAddress,
            desiredTokenId: desiredTokenId,
            desiredErc1155Quantity: desiredErc1155Quantity
        });

        s.tokenToListingIds[tokenAddress][tokenId].push(newListingId);

        if (buyerWhitelistEnabled) {
            if (allowedBuyers.length > 0) {
                // delegate into BuyerWhitelistFacet on this Diamond
                IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(newListingId, allowedBuyers);
            }
        } else {
            if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();
        }

        emit ListingCreated(
            s.listingIdCounter,
            tokenAddress,
            tokenId,
            erc1155Quantity,
            price,
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
    /// @param expectedPrice Caller’s view of `listing.price` to guard against mid-tx updates.
    /// @param expectedErc1155Quantity Caller’s view of `listing.erc1155Quantity` to guard against mid-tx updates.
    /// @param expectedDesiredTokenAddress Caller’s view of `listing.desiredTokenAddress` to guard against mid-tx updates.
    /// @param expectedDesiredTokenId Caller’s view of `listing.desiredTokenId` to guard against mid-tx updates.
    /// @param expectedDesiredErc1155Quantity Caller’s view of `listing.desiredErc1155Quantity` to guard against mid-tx updates.
    /// @param erc1155PurchaseQuantity For ERC-1155: exact units to purchase (0 for ERC-721).
    /// @param desiredErc1155Holder If fulfilling an ERC-1155 swap, the holder whose balance/approval is checked for the desired token.
    /// @dev Reverts if: collection de-whitelisted; buyer not whitelisted (when enabled); terms mismatch (front-run protection);
    /// invalid purchase quantity; partial buy disallowed; `msg.value` < computed price; seller equals buyer; seller no longer owns/approved;
    /// royalty exceeds proceeds; swap balance/approval insufficient.
    /// Accounting: fee = `price * feeRate / 100_000`, royalty (ERC-2981) deducted from seller proceeds, excess ETH credited to buyer’s `proceeds`.
    /// For swap listings, buyer’s desired NFT is transferred to the seller before receiving the listed NFT.
    /// Deprecated listings by the swap seller for that token are cleaned (swap-and-pop) if they can no longer be fulfilled.
    /// If a whitelisted token is removed from the collection whitelist after being listed, the listing becomes unpurchasable and must be cleaned up using the cleanListing function. This cleanup process is handled by an offchain bot.
    function purchaseListing(
        uint128 listingId,
        uint256 expectedPrice,
        uint256 expectedErc1155Quantity,
        address expectedDesiredTokenAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredErc1155Quantity,
        uint256 erc1155PurchaseQuantity,
        address desiredErc1155Holder
    ) external payable nonReentrant listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[listingId];

        // Block purchase if the collection was de-whitelisted after listing
        if (!s.whitelistedCollections[listedItem.tokenAddress]) {
            revert IdeationMarket__CollectionNotWhitelisted(listedItem.tokenAddress);
        }

        // BuyerWhitelist Check
        if (listedItem.buyerWhitelistEnabled) {
            if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {
                revert IdeationMarket__BuyerNotWhitelisted(listingId, msg.sender);
            }
        }

        // Check if Terms have changed in the meantime to guard against mid-tx updates
        if (
            listedItem.price != expectedPrice || listedItem.desiredTokenAddress != expectedDesiredTokenAddress
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
            purchasePrice = listedItem.price * erc1155PurchaseQuantity / listedItem.erc1155Quantity;
        }

        if (msg.value < purchasePrice) {
            revert IdeationMarket__PriceNotMet(listedItem.listingId, purchasePrice, msg.value);
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
            requireERC1155Approval(listedItem.tokenAddress, listedItem.seller);
        } else {
            address ownerToken = IERC721(listedItem.tokenAddress).ownerOf(listedItem.tokenId);
            if (ownerToken != listedItem.seller) {
                revert IdeationMarket__SellerNotTokenOwner(listingId);
            }
            requireERC721Approval(listedItem.tokenAddress, listedItem.tokenId);
        }

        // Calculate the innovation fee based on the listing feeRate (e.g., 1_000 for 1% with a denominator of 100_000)
        uint256 innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000);

        // Seller receives sale price minus the innovation fee
        uint256 sellerProceeds = purchasePrice - innovationProceeds;

        // in case there is a ERC2981 Royalty defined, Royalties will get deducted from the sellerProceeds aswell and added to the proceeds of the Royalty Receiver
        if (IERC165(listedItem.tokenAddress).supportsInterface(type(IERC2981).interfaceId)) {
            (address royaltyReceiver, uint256 royaltyAmount) =
                IERC2981(listedItem.tokenAddress).royaltyInfo(listedItem.tokenId, purchasePrice);
            if (royaltyAmount > 0) {
                if (sellerProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();
                sellerProceeds -= royaltyAmount; // NFT royalties get deducted from the sellerProceeds
                s.proceeds[royaltyReceiver] += royaltyAmount; // Update proceeds for the Royalty Receiver
                emit RoyaltyPaid(listingId, royaltyReceiver, listedItem.tokenAddress, listedItem.tokenId, royaltyAmount);
            }
        }

        // handle excess payment
        uint256 excessPayment = msg.value - purchasePrice;

        // Update proceeds for the seller, marketplace owner and potentially buyer
        s.proceeds[listedItem.seller] += sellerProceeds;
        s.proceeds[LibDiamond.contractOwner()] += innovationProceeds;
        if (excessPayment > 0) {
            s.proceeds[msg.sender] += excessPayment;
        }

        // in case it's a swap listing, send that desired token (the frontend approves the marketplace for that action beforehand)
        if (listedItem.desiredTokenAddress != address(0)) {
            address desiredOwner = address(0); // initializing this for cleanup
            address obsoleteSeller = address(0); // initializing this for cleanup
            uint256 remainingERC1155Balance = 0; // initializing this for cleanup
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
                requireERC1155Approval(listedItem.desiredTokenAddress, desiredErc1155Holder);

                // Perform the safe swap transfer buyer to seller.
                IERC1155(listedItem.desiredTokenAddress).safeTransferFrom(
                    desiredErc1155Holder,
                    listedItem.seller,
                    listedItem.desiredTokenId,
                    listedItem.desiredErc1155Quantity,
                    ""
                );

                obsoleteSeller = desiredErc1155Holder; // for cleanup
                remainingERC1155Balance = desiredToken.balanceOf(obsoleteSeller, listedItem.desiredTokenId); // for cleanup
            } else {
                IERC721 desiredToken = IERC721(listedItem.desiredTokenAddress);
                desiredOwner = desiredToken.ownerOf(listedItem.desiredTokenId);
                // For ERC721: Check ownership.
                if (
                    msg.sender != desiredOwner && msg.sender != desiredToken.getApproved(listedItem.desiredTokenId)
                        && !desiredToken.isApprovedForAll(desiredOwner, msg.sender)
                ) {
                    revert IdeationMarket__NotAuthorizedOperator();
                }

                // Check approval
                requireERC721Approval(listedItem.desiredTokenAddress, listedItem.desiredTokenId);

                // Perform the safe swap transfer buyer to seller.
                desiredToken.safeTransferFrom(desiredOwner, listedItem.seller, listedItem.desiredTokenId);

                obsoleteSeller = desiredOwner; // for cleanup
            }

            // in case the desiredToken is listed already, delete that now deprecated listing to cleanup
            uint128[] storage deprecatedListingArray =
                s.tokenToListingIds[listedItem.desiredTokenAddress][listedItem.desiredTokenId];

            for (uint256 i = deprecatedListingArray.length; i != 0;) {
                unchecked {
                    i--;
                }
                uint128 depId = deprecatedListingArray[i];
                Listing storage dep = s.listings[depId];
                // If the seller of that listing is the same as the obsoleteSeller (the one who just sold his token to the current buyer)
                // and in case of an ERC1155 listing, if the obsoleteSeller does not hold enough token anymore to cover the
                // desiredErc1155Quantity of that listing, that listing needs to get removed. If it is an erc721 listing,
                // it's enough that the obsoleteSeller is the seller of that listing, to remove that listing.
                if (
                    dep.seller == obsoleteSeller
                        && (listedItem.desiredErc1155Quantity == 0 || dep.erc1155Quantity > remainingERC1155Balance)
                ) {
                    // remove the obsolete listing
                    delete s.listings[depId];
                    emit ListingCanceled(
                        depId, listedItem.desiredTokenAddress, listedItem.desiredTokenId, obsoleteSeller, address(this)
                    );
                    deprecatedListingArray[i] = deprecatedListingArray[deprecatedListingArray.length - 1];
                    deprecatedListingArray.pop();
                }
            }
        }

        // Update or delete the listing
        bool partialBuy = false;
        if (erc1155PurchaseQuantity == listedItem.erc1155Quantity) {
            // fully bought → remove
            deleteListingAndCleanup(s, listingId, listedItem.tokenAddress, listedItem.tokenId);
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

        emit ListingPurchased(
            listedItem.listingId,
            listedItem.tokenAddress,
            listedItem.tokenId,
            erc1155PurchaseQuantity,
            partialBuy,
            purchasePrice,
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
            deleteListingAndCleanup(s, listingId, listedItem.tokenAddress, listedItem.tokenId);
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
            deleteListingAndCleanup(s, listingId, listedItem.tokenAddress, listedItem.tokenId);
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
        address newDesiredTokenAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredErc1155Quantity,
        uint256 newErc1155Quantity,
        bool newBuyerWhitelistEnabled,
        bool newPartialBuyEnabled,
        address[] calldata newAllowedBuyers
    ) external listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[listingId];

        // cache variables for gas efficiency
        address tokenAddress = listedItem.tokenAddress;
        address seller = listedItem.seller;
        uint256 tokenId = listedItem.tokenId;
        uint256 erc1155Quantity = listedItem.erc1155Quantity;

        // ensure the newQuantity is still valid according to the token Standard ( 0 for ERC721, >0 for ERC1155)
        if (newErc1155Quantity > 0) {
            if (erc1155Quantity == 0) {
                revert IdeationMarket__WrongQuantityParameter();
            }
        } else {
            if (erc1155Quantity > 0) {
                revert IdeationMarket__WrongQuantityParameter();
            }
        }

        // check if the user is an authorized operator and use interface check to ensure the MarketPlace is still Approved for transfer and seller holds enough token
        if (newErc1155Quantity > 0) {
            IERC1155 token = IERC1155(tokenAddress);
            // check if the user is authorized
            if (msg.sender != seller && !token.isApprovedForAll(seller, msg.sender)) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            uint256 balance = token.balanceOf(seller, tokenId);
            if (balance < newErc1155Quantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(newErc1155Quantity, balance);
            }
            requireERC1155Approval(tokenAddress, seller);
        } else {
            IERC721 token = IERC721(tokenAddress);
            address tokenHolder = token.ownerOf(tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != token.getApproved(tokenId)
                    && !token.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            requireERC721Approval(tokenAddress, tokenId);
        }

        //Validates collection whitelist status. If the collection was de-whitelisted after the original listing,
        // the listing is automatically canceled and `CollectionWhitelistRevokedCancelTriggered` is emitted.
        if (!s.whitelistedCollections[tokenAddress]) {
            cancelListing(listingId);
            emit CollectionWhitelistRevokedCancelTriggered(listingId, tokenAddress);
            return;
        }

        // check validity of newPartialBuyEnabled Flag
        if (newErc1155Quantity <= 1 && newPartialBuyEnabled) {
            revert IdeationMarket__PartialBuyNotPossible();
        }

        // if partial buys allowed, require even per-unit price
        if (newPartialBuyEnabled) {
            // price must be divisible by quantity
            if (newPrice % newErc1155Quantity != 0) {
                revert IdeationMarket__InvalidUnitPrice();
            }
            // forbid partialbuys if its a swap listing
            if (newDesiredTokenAddress != address(0)) {
                revert IdeationMarket__PartialBuyNotPossible();
            }
        }

        validateSwapParameters(
            tokenAddress, tokenId, newPrice, newDesiredTokenAddress, newDesiredTokenId, newDesiredErc1155Quantity
        );

        listedItem.price = newPrice;
        listedItem.desiredTokenAddress = newDesiredTokenAddress;
        listedItem.desiredTokenId = newDesiredTokenId;
        listedItem.desiredErc1155Quantity = newDesiredErc1155Quantity;
        listedItem.erc1155Quantity = newErc1155Quantity;
        listedItem.feeRate = s.innovationFee;
        listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled;
        listedItem.partialBuyEnabled = newPartialBuyEnabled;

        if (newBuyerWhitelistEnabled) {
            if (newAllowedBuyers.length > 0) {
                // delegate into BuyerWhitelistFacet on this Diamond
                IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId, newAllowedBuyers);
            }
        } else {
            if (newAllowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();
        }

        emit ListingUpdated(
            listedItem.listingId,
            tokenAddress,
            tokenId,
            newErc1155Quantity,
            newPrice,
            listedItem.feeRate,
            seller,
            newBuyerWhitelistEnabled,
            newPartialBuyEnabled,
            newDesiredTokenAddress,
            newDesiredTokenId,
            newDesiredErc1155Quantity
        );
    }

    /// @notice Withdraws the caller’s accumulated ETH proceeds.
    /// @dev Reverts `IdeationMarket__NoProceeds` if zero. Sets balance to zero before transferring.
    /// Emits `ProceedsWithdrawn`. Reverts `IdeationMarket__TransferFailed` on failed call.
    function withdrawProceeds() external nonReentrant {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 proceeds = s.proceeds[msg.sender];

        if (proceeds == 0) {
            revert IdeationMarket__NoProceeds();
        }

        s.proceeds[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: proceeds}("");
        if (!success) {
            revert IdeationMarket__TransferFailed();
        }
        emit ProceedsWithdrawn(msg.sender, proceeds);
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
            deleteListingAndCleanup(s, listingId, listedItem.tokenAddress, listedItem.tokenId);
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

    /// @notice Requires this diamond to be approved to transfer the ERC-721 token.
    /// @dev Accepts either token-level approval (`getApproved`) or operator approval (`isApprovedForAll`).
    /// Reverts `IdeationMarket__NotApprovedForMarketplace` if neither is set.
    function requireERC721Approval(address tokenAddress, uint256 tokenId) internal view {
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
    function requireERC1155Approval(address tokenAddress, address tokenOwner) internal view {
        if (!IERC1155(tokenAddress).isApprovedForAll(tokenOwner, address(this))) {
            revert IdeationMarket__NotApprovedForMarketplace();
        }
    }

    /// @notice Validates swap configuration for a listing.
    /// @dev Disallows swapping for the same token (same contract + id).
    /// Non-swap: `desiredTokenAddress == 0`, `desiredTokenId == 0`, `desiredErc1155Quantity == 0`, and `price > 0`.
    /// Swap ERC-1155: `desiredErc1155Quantity > 0` and desired contract must support ERC-1155.
    /// Swap ERC-721: `desiredErc1155Quantity == 0` and desired contract must support ERC-721.
    function validateSwapParameters(
        address tokenAddress,
        uint256 tokenId,
        uint256 price,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    ) private view {
        if (tokenAddress == desiredTokenAddress && tokenId == desiredTokenId) {
            revert IdeationMarket__NoSwapForSameToken();
        }

        if (desiredTokenAddress == address(0)) {
            if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (desiredErc1155Quantity != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (price == 0) revert IdeationMarket__FreeListingsNotSupported();
        } else if (desiredErc1155Quantity > 0) {
            if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        } else if (desiredErc1155Quantity == 0) {
            if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        }
    }

    /// @notice Deletes a listing and removes its id from the reverse index for (tokenAddress, tokenId).
    /// @dev Uses swap-and-pop on `tokenToListingIds[tokenAddress][tokenId]` to keep the array compact.
    function deleteListingAndCleanup(AppStorage storage s, uint128 listingId, address tokenAddress, uint256 tokenId)
        internal
    {
        delete s.listings[listingId];

        uint128[] storage listingArray = s.tokenToListingIds[tokenAddress][tokenId];
        for (uint256 i = listingArray.length; i != 0;) {
            unchecked {
                i--;
            }
            if (listingArray[i] == listingId) {
                listingArray[i] = listingArray[listingArray.length - 1];
                listingArray.pop();
            }
        }
    }

    /////////////////////
    // View Functions  //
    /////////////////////

    // Note: Getter functions are implemented in GetterFacet.sol
    // to maintain separation of concerns in the diamond pattern
}
