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

    // Event emitted when a listing is canceled due to revoked approval.
    event ListingCanceledDueToMissingApproval(
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

    modifier listingExists(uint128 listingId) {
        if (LibAppStorage.appStorage().listings[listingId].seller == address(0)) revert IdeationMarket__NotListed();
        _;
    }

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

    /*
     * @notice Method for listing your NFT on the marketplace
     * @param tokenAddress: Address of the NFT to be listed
     * @param tokenId: TokenId of that NFT
     * @param price: The price the owner wants the NFT to sell for
     * @dev: Using approve() the user keeps on owning the NFT while it is listed
     */

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

        // check if the user is an authorized Operator
        if (erc1155Quantity > 0) {
            // check that the quantity matches the token Type
            if (!IERC165(tokenAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__WrongQuantityParameter();
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
        } else {
            // check that the quantity matches the token Type
            if (!IERC165(tokenAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__WrongQuantityParameter();
            }
            IERC721 token = IERC721(tokenAddress);
            address tokenHolder = token.ownerOf(tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != token.getApproved(tokenId)
                    && !token.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
        }

        // check validity of partialBuyEnabled Flag
        if (erc1155Quantity <= 1) {
            if (partialBuyEnabled) {
                revert IdeationMarket__PartialBuyNotPossible();
            }
        }

        // if partial buys allowed, require even per-unit price
        if (partialBuyEnabled) {
            // price must be divisible by quantity
            if (price % erc1155Quantity != 0) {
                revert IdeationMarket__InvalidUnitPrice();
            }
        }

        // Prevent relisting an already-listed ERC721 NFT
        if (erc1155Quantity == 0 && s.tokenToListingIds[tokenAddress][tokenId].length > 0) {
            revert IdeationMarket__AlreadyListed();
        }

        // Swap-specific check
        validateSwapParameters(
            tokenAddress, tokenId, price, desiredTokenAddress, desiredTokenId, desiredErc1155Quantity
        );

        // if the interacting user is an approved Operator set the token Owner as the seller
        address seller = (erc1155Holder != address(0)) ? erc1155Holder : msg.sender;

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
            // delegate into BuyerWhitelistFacet on this Diamond
            IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(newListingId, allowedBuyers);
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

    function purchaseListing(
        uint128 listingId,
        uint256 expectedPrice,
        uint256 expectedErc1155Quantity,
        address expectedDesiredTokenAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredErc1155Quantity,
        uint256 erc1155PurchaseQuantity, // the exact ERC1155 quantity the buyer wants when partialBuyEnabled = true; for ERC721 must be 0
        address desiredErc1155Holder // if it is a swap listing where the desired token is an erc1155, the buyer needs to specify the owner of that erc1155, because in case he is not the owner but authorized, the marketplace needs this info to check the approval
    ) external payable nonReentrant listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[listingId];

        // BuyerWhitelist Check
        if (listedItem.buyerWhitelistEnabled) {
            if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {
                revert IdeationMarket__BuyerNotWhitelisted(listingId, msg.sender);
            }
        }

        // Check if Terms have changed in the meantime (frontrunning Attack)
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

        // setting the purchePrice based on partialBuy quantity
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
            if (balance < listedItem.erc1155Quantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(listedItem.erc1155Quantity, balance);
            }
            requireERC1155Approval(listedItem.tokenAddress, listedItem.seller);
        } else {
            address ownerToken = IERC721(listedItem.tokenAddress).ownerOf(listedItem.tokenId);
            if (ownerToken != listedItem.seller) {
                revert IdeationMarket__SellerNotTokenOwner(listingId);
            }
            requireERC721Approval(listedItem.tokenAddress, listedItem.tokenId);
        }

        // Calculate the innovation fee based on the listing feeRate (e.g., 2000 for 2% with a denominator of 100000)
        uint256 innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000);

        // Seller receives sale price minus the innovation fee
        uint256 sellerProceeds = purchasePrice - innovationProceeds;

        // in case there is a ERC2981 Royalty defined, Royalties will get deducted from the sellerProceeds aswell
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
            address desiredOwner = address(0); // initializing this for erc721 cleanup
            uint256 remainingBalance = 0; // initializing this for erc1155 cleanup
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

                remainingBalance = swapBalance - listedItem.desiredErc1155Quantity + 1; // using this +1 trick for the '<=' comparison in the cleanup

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
            }

            // in case the desiredToken is listed already, delete that now deprecated listing to cleanup
            uint128[] storage deprecatedListingArray =
                s.tokenToListingIds[listedItem.desiredTokenAddress][listedItem.desiredTokenId];

            address obsoleteSeller = (listedItem.desiredErc1155Quantity > 0)
                ? desiredErc1155Holder // ERC-1155 swap
                : desiredOwner; // ERC-721 swap

            for (uint256 i = deprecatedListingArray.length; i != 0;) {
                unchecked {
                    i--;
                }
                uint128 depId = deprecatedListingArray[i];

                if (s.listings[depId].seller == obsoleteSeller && remainingBalance <= s.listings[depId].erc1155Quantity)
                {
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

    // natspec info: the token owner or authorized operator is able to cancel the listing of their NFT, but also the Governance holder of the marketplace is able to cancel any listing in case there are issues with a listing
    function cancelListing(uint128 listingId) public listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[listingId];

        address diamondOwner = LibDiamond.contractOwner();
        bool isAuthorized;
        if (listedItem.erc1155Quantity == 0) {
            IERC721 token = IERC721(listedItem.tokenAddress);
            isAuthorized = (
                msg.sender == listedItem.seller || msg.sender == token.getApproved(listedItem.tokenId)
                    || token.isApprovedForAll(listedItem.seller, msg.sender)
            );
        } else {
            isAuthorized = (
                msg.sender == listedItem.seller
                    || IERC1155(listedItem.tokenAddress).isApprovedForAll(listedItem.seller, msg.sender)
            );
        }
        // allows the diamondOwner to cancel any Listing
        if (!isAuthorized && msg.sender != diamondOwner) {
            revert IdeationMarket__NotAuthorizedToCancel();
        }

        // delete Listing
        deleteListingAndCleanup(s, listingId, listedItem.tokenAddress, listedItem.tokenId);

        emit ListingCanceled(listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.seller, msg.sender);
    }

    function updateListing(
        uint128 listingId,
        uint256 newPrice,
        address newDesiredTokenAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 newErc1155Quantity, // >0 for ERC1155, 0 for only ERC721
        bool newBuyerWhitelistEnabled,
        bool newPartialBuyEnabled,
        address[] calldata newAllowedBuyers // whitelisted Buyers
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

        // check if the user is an authorized operator and Use interface check to ensure the MarketPlace is still Approved for transfer and holds enough token
        if (newErc1155Quantity > 0) {
            IERC1155 token = IERC1155(tokenAddress);
            // check if the user is authorized
            if (msg.sender != seller && !token.isApprovedForAll(seller, msg.sender)) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            uint256 balance = token.balanceOf(seller, tokenId);
            if (balance < erc1155Quantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(erc1155Quantity, balance);
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

        // check if the Collection is still Whitelisted - even tho it would not have been able to get listed in the first place, if the collection has been revoked in the meantime, updating would cancel the listing
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
        }

        // Swap-specific check
        validateSwapParameters(
            tokenAddress, tokenId, newPrice, newDesiredTokenAddress, newDesiredTokenId, newDesiredErc1155Quantity
        );

        listedItem.price = newPrice;
        listedItem.desiredTokenAddress = newDesiredTokenAddress;
        listedItem.desiredTokenId = newDesiredTokenId;
        listedItem.desiredErc1155Quantity = newDesiredErc1155Quantity;
        listedItem.erc1155Quantity = newErc1155Quantity;
        listedItem.feeRate = s.innovationFee; // note that with updating a listing the up to date innovationFee will be set
        listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled; // other than in the createListing function where the buyerWhitelist gets passed withing creating the listing, when setting the buyerWhitelist from originally false to true through the updateListing function, the whitelist has to get filled through additional calling of the addBuyerWhitelistAddresses function
        listedItem.partialBuyEnabled = newPartialBuyEnabled;

        if (newBuyerWhitelistEnabled) {
            // delegate into BuyerWhitelistFacet on this Diamond
            IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId, newAllowedBuyers);
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

    function setInnovationFee(uint32 newFee) external {
        LibDiamond.enforceIsContractOwner();
        AppStorage storage s = LibAppStorage.appStorage();
        uint32 previousFee = s.innovationFee;
        s.innovationFee = newFee;
        emit InnovationFeeUpdated(previousFee, newFee);
    }

    // checks for token contract approval and for collection whitelist
    function cleanListing(uint128 listingId) external listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[listingId];

        bool approved = false;

        // check if the Collection is still Whitelisted
        if (s.whitelistedCollections[listedItem.tokenAddress]) {
            // check approval depending on token type
            if (listedItem.erc1155Quantity > 0) {
                approved = IERC1155(listedItem.tokenAddress).isApprovedForAll(listedItem.seller, address(this));
            } else {
                IERC721 token = IERC721(listedItem.tokenAddress);
                approved = token.getApproved(listedItem.tokenId) == address(this)
                    || token.isApprovedForAll(listedItem.seller, address(this));
            }
        }

        // If approval is missing, cancel the listing by deleting it from storage.
        if (!approved) {
            deleteListingAndCleanup(s, listingId, listedItem.tokenAddress, listedItem.tokenId);

            emit ListingCanceledDueToMissingApproval(
                listingId, listedItem.tokenAddress, listedItem.tokenId, listedItem.seller, msg.sender
            );
        } else {
            revert IdeationMarket__StillApproved();
        }
    }

    //////////////////////
    // Helper Functions //
    //////////////////////

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

    function requireERC1155Approval(address tokenAddress, address tokenOwner) internal view {
        if (!IERC1155(tokenAddress).isApprovedForAll(tokenOwner, address(this))) {
            revert IdeationMarket__NotApprovedForMarketplace();
        }
    }

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
            if (price <= 0) revert IdeationMarket__FreeListingsNotSupported();
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

    // find the getter functions in the GetterFacet.sol
}
