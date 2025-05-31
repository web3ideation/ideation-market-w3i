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
error IdeationMarket__SellerNotNftOwner(uint128 listingId);
error IdeationMarket__NotAuthorizedOperator();
error IdeationMarket__ListingTermsChanged();
error IdeationMarket__FreeListingsNotSupported();
error IdeationMarket__PriceNotMet(uint256 listingId, uint256 price, uint256 value);
error IdeationMarket__NoProceeds();
error IdeationMarket__SameBuyerAsSeller();
error IdeationMarket__NoSwapForSameNft();
error IdeationMarket__NotSupportedTokenStandard();
error IdeationMarket__NotListed();
error IdeationMarket__Reentrant();
error IdeationMarket__CollectionNotWhitelisted(address nftAddress);
error IdeationMarket__BuyerNotWhitelisted(uint128 listingId, address buyer);
error IdeationMarket__InvalidNoSwapParameters();
error IdeationMarket__SellerInsufficientTokenBalance(uint256 required, uint256 available);
error IdeationMarket__RoyaltyFeeExceedsProceeds();
error IdeationMarket__NotAuthorizedToCancel();
error IdeationMarket__NotOwnerOfDesiredSwap();
error IdeationMarket__TransferFailed();
error IdeationMarket__InsufficientSwapTokenBalance(uint256 required, uint256 available);
error IdeationMarket__WhitelistNotAllowed();
error IdeationMarket__WrongErc1155HolderParameter();
error IdeationMarket__WrongQuantityParameter();

contract IdeationMarketFacet {
    /**
     * @notice Emitted when an item is listed on the marketplace.
     * @param listingId The listing ID.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The token ID being listed.
     * @param price Listing price.
     * @param seller The address of the seller.
     * @param desiredNftAddress The desired NFT address for swaps (0 for non-swap listing).
     * @param desiredTokenId The desired token ID for swaps (only applicable for swap listing).
     * @param feeRate innovationFee rate at the time of listing in case it gets updated before selling.
     * @param quantity Quantity (for ERC1155 tokens; must be 0 for ERC721).
     */
    event ItemListed(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 quantity,
        uint256 price,
        uint256 feeRate,
        address seller,
        bool buyerWhitelistEnabled,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity
    );

    event ItemBought(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 quantity,
        uint256 price,
        uint256 feeRate,
        address seller,
        address buyer,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity
    );

    event ItemCanceled(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        address seller,
        address triggeredBy
    );

    event ItemUpdated(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 quantity,
        uint256 price,
        uint256 feeRate,
        address seller,
        bool buyerWhitelistEnabled,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity
    );

    event ProceedsWithdrawn(address indexed withdrawer, uint256 amount);

    event InnovationFeeUpdated(uint256 previousFee, uint256 newFee);

    // Event emitted when a listing is canceled due to revoked approval.
    event ItemCanceledDueToMissingApproval(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        address seller,
        address triggeredBy
    );

    event RoyaltyPaid(
        uint256 indexed listingId,
        address indexed royaltyReceiver,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 royaltyAmount
    );

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

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
     * @param nftAddress: Address of the NFT to be listed
     * @param tokenId: TokenId of that NFT
     * @param price: The price the owner wants the NFT to sell for
     * @dev: Using approve() the user keeps on owning the NFT while it is listed
     */

    function listItem(
        address nftAddress,
        uint256 tokenId,
        address erc1155Holder,
        uint96 price,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 quantity, // >0 for ERC1155, 0 for only ERC721
        bool buyerWhitelistEnabled,
        address[] calldata allowedBuyers // whitelisted Buyers
    ) external {
        // check if the user is an authorized Operator
        if (quantity > 0) {
            IERC1155 nft = IERC1155(nftAddress);
            // check if the user is authorized or the holder himself
            if (msg.sender != erc1155Holder && !nft.isApprovedForAll(erc1155Holder, msg.sender)) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            // check that this 'erc1155Holder' is really the holder
            if (nft.balanceOf(erc1155Holder, tokenId) == 0) {
                revert IdeationMarket__WrongErc1155HolderParameter();
            }
        } else {
            IERC721 nft = IERC721(nftAddress);
            address tokenHolder = nft.ownerOf(tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != nft.getApproved(tokenId)
                    && !nft.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
        }
        AppStorage storage s = LibAppStorage.appStorage();

        // check if the Collection is Whitelisted
        if (!s.whitelistedCollections[nftAddress]) {
            revert IdeationMarket__CollectionNotWhitelisted(nftAddress);
        }

        // Prevent relisting an already-listed ERC721 NFT
        if (quantity == 0 && s.nftTokenToListingIds[nftAddress][tokenId].length > 0) {
            revert IdeationMarket__AlreadyListed();
        }

        // Swap-specific check
        if (nftAddress == desiredNftAddress && tokenId == desiredTokenId) {
            revert IdeationMarket__NoSwapForSameNft();
        }
        if (desiredNftAddress == address(0)) {
            if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (desiredQuantity != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (price <= 0) revert IdeationMarket__FreeListingsNotSupported();
        } else if (desiredQuantity > 0) {
            if (!IERC165(desiredNftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        } else if (desiredQuantity == 0) {
            if (!IERC165(desiredNftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        }

        // if the interacting user is an approved Operator set the token Owner as the seller
        address seller = (erc1155Holder != address(0)) ? erc1155Holder : msg.sender;

        // ensure the quantity matches the token Type and the MarketPlace has been Approved for transfer.
        if (quantity > 0) {
            if (!IERC165(nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__WrongQuantityParameter();
            }
            check1155Approval(nftAddress, seller); // !!! the approval function needs to keep the nftAddress parameter bc the listing isnt there yet - recheck that
        } else {
            if (!IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__WrongQuantityParameter();
            }

            check721Approval(nftAddress, tokenId);
        }

        s.listingIdCounter++;

        uint128 newListingId = s.listingIdCounter;

        s.listings[newListingId] = Listing({ // !!! I added the nftAddress and tokenId and changed the position of quantity and buyerWhitelistEnabled - check that this is implemented EVERYWHERE!
            listingId: newListingId,
            nftAddress: nftAddress,
            tokenId: tokenId,
            quantity: quantity,
            price: price,
            feeRate: s.innovationFee,
            seller: seller,
            buyerWhitelistEnabled: buyerWhitelistEnabled,
            desiredNftAddress: desiredNftAddress,
            desiredTokenId: desiredTokenId,
            desiredQuantity: desiredQuantity
        });

        s.nftTokenToListingIds[nftAddress][tokenId].push(newListingId);

        if (buyerWhitelistEnabled) {
            // delegate into BuyerWhitelistFacet on this Diamond
            IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(newListingId, allowedBuyers);
        } else {
            if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistNotAllowed();
        }

        emit ItemListed(
            s.listingIdCounter,
            nftAddress,
            tokenId,
            quantity,
            price,
            s.innovationFee,
            seller,
            buyerWhitelistEnabled,
            desiredNftAddress,
            desiredTokenId,
            desiredQuantity
        );
    }

    function buyItem(
        uint128 listingId,
        uint256 expectedQuantity,
        address expectedDesiredNftAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredQuantity,
        address desiredErc1155Holder // if it is a swap listing where the desired nft is an erc1155, the buyer needs to specify the owner of that erc1155, because in case he is not the owner but authorized, the marketplace needs this info to check the approval
    ) external payable nonReentrant listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[listingId];

        // BuyerWhitelist Check
        if (listedItem.buyerWhitelistEnabled) {
            if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {
                revert IdeationMarket__BuyerNotWhitelisted(listingId, msg.sender);
            }
        }

        if (msg.value < listedItem.price) {
            revert IdeationMarket__PriceNotMet(listedItem.listingId, listedItem.price, msg.value);
        }

        if (
            listedItem.desiredNftAddress != expectedDesiredNftAddress
                || listedItem.desiredTokenId != expectedDesiredTokenId
                || listedItem.desiredQuantity != expectedDesiredQuantity || listedItem.quantity != expectedQuantity
        ) {
            revert IdeationMarket__ListingTermsChanged();
        }

        if (listedItem.desiredQuantity > 0 && desiredErc1155Holder == address(0)) {
            revert IdeationMarket__WrongErc1155HolderParameter();
        }

        if (msg.sender == listedItem.seller) {
            revert IdeationMarket__SameBuyerAsSeller();
        }

        // Check if the seller still owns the token and if the marketplace is still approved
        if (listedItem.quantity > 0) {
            uint256 balance = IERC1155(listedItem.nftAddress).balanceOf(listedItem.seller, listedItem.tokenId);
            if (balance < listedItem.quantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(listedItem.quantity, balance);
            }
            check1155Approval(listedItem.nftAddress, listedItem.seller);
        } else {
            address ownerToken = IERC721(listedItem.nftAddress).ownerOf(listedItem.tokenId);
            if (ownerToken != listedItem.seller) {
                revert IdeationMarket__SellerNotNftOwner(listingId);
            }
            check721Approval(listedItem.nftAddress, listedItem.tokenId);
        }

        // Calculate the innovation fee based on the listing feeRate (e.g., 2000 for 2% with a denominator of 100000)
        uint256 innovationFee = ((listedItem.price * listedItem.feeRate) / 100000);

        // Seller receives sale price minus the innovation fee
        uint256 sellerProceeds = listedItem.price - innovationFee;

        // in case there is a ERC2981 Royalty defined, Royalties will get deducted from the sellerProceeds aswell
        if (IERC165(listedItem.nftAddress).supportsInterface(type(IERC2981).interfaceId)) {
            (address royaltyReceiver, uint256 royaltyAmount) =
                IERC2981(listedItem.nftAddress).royaltyInfo(listedItem.tokenId, listedItem.price);
            if (royaltyAmount > 0) {
                if (sellerProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();
                sellerProceeds -= royaltyAmount; // NFT royalties get deducted from the sellerProceeds
                s.proceeds[royaltyReceiver] += royaltyAmount; // Update proceeds for the Royalty Receiver
                emit RoyaltyPaid(listingId, royaltyReceiver, listedItem.nftAddress, listedItem.tokenId, royaltyAmount);
            }
        }

        // handle excess payment
        uint256 excessPayment = msg.value - listedItem.price;

        // Update proceeds for the seller, marketplace owner and potentially buyer

        s.proceeds[listedItem.seller] += sellerProceeds;
        s.proceeds[LibDiamond.contractOwner()] += innovationFee;
        if (excessPayment > 0) {
            s.proceeds[msg.sender] += excessPayment;
        }

        // in case it's a swap listing, send that desired nft (the frontend approves the marketplace for that action beforehand)
        if (listedItem.desiredNftAddress != address(0)) {
            if (listedItem.desiredQuantity > 0) {
                // For ERC1155: Check that buyer holds enough token.
                IERC1155 desiredNft = IERC1155(listedItem.desiredNftAddress);
                uint256 swapBalance = desiredNft.balanceOf(desiredErc1155Holder, listedItem.desiredTokenId);
                if (swapBalance == 0) revert IdeationMarket__WrongErc1155HolderParameter();
                if (
                    desiredNft.balanceOf(msg.sender, listedItem.desiredTokenId) == 0
                        && !desiredNft.isApprovedForAll(desiredErc1155Holder, msg.sender)
                ) {
                    revert IdeationMarket__NotAuthorizedOperator();
                }
                if (swapBalance < listedItem.desiredQuantity) {
                    revert IdeationMarket__InsufficientSwapTokenBalance(listedItem.desiredQuantity, swapBalance);
                }

                // Check approval
                check1155Approval(listedItem.desiredNftAddress, desiredErc1155Holder);

                // Perform the safe swap transfer buyer to seller.
                IERC1155(listedItem.desiredNftAddress).safeTransferFrom(
                    desiredErc1155Holder, listedItem.seller, listedItem.desiredTokenId, listedItem.desiredQuantity, ""
                );
            } else {
                IERC721 desiredNft = IERC721(listedItem.desiredNftAddress);
                address desiredOwner = desiredNft.ownerOf(listedItem.desiredTokenId);
                // For ERC721: Check ownership.
                if (
                    msg.sender != desiredOwner && msg.sender != desiredNft.getApproved(listedItem.desiredTokenId)
                        && !desiredNft.isApprovedForAll(desiredOwner, msg.sender)
                ) {
                    revert IdeationMarket__NotAuthorizedOperator();
                }

                // Check approval
                check721Approval(listedItem.desiredNftAddress, listedItem.desiredTokenId);

                // Perform the safe swap transfer buyer to seller.
                desiredNft.safeTransferFrom(msg.sender, listedItem.seller, listedItem.desiredTokenId);
            }

            // in case the desiredNft is listed already, delete that now deprecated listing // !!! let cGPT check this again // !!! I think this is only applicable for erc1155 not erc721 but is processed with erc721...
            uint128[] storage listingArray =
                s.nftTokenToListingIds[listedItem.desiredNftAddress][listedItem.desiredTokenId];
            for (uint256 i; i < listingArray.length; ++i) {
                if (
                    s.listings[listingArray[i]].seller == desiredErc1155Holder /* !!! && desiredErc1155Holder.balance < s.listings[listingArray[i]].quantity */
                ) {
                    s.listings[listingArray[i]].seller = address(0); // indicating that this Listing is not active
                    listingArray[i] = listingArray[listingArray.length - 1];
                    emit ItemCanceled(
                        listingArray[i],
                        listedItem.desiredNftAddress,
                        listedItem.desiredTokenId,
                        desiredErc1155Holder,
                        address(this)
                    );
                    listingArray.pop();
                    // !!! should i 'break;' here or is it possible that there might be two listingmappings to delete?
                }
            }
        }

        delete (s.listings[listedItem.listingId]); // !!! change this to just setting the seller to 0 instead of deleting the whole thing

        // !!! also remove it from the reverse lookup nftTokenToListingIds

        // Transfer tokens based on the token standard.
        if (listedItem.quantity > 0) {
            IERC1155(listedItem.nftAddress).safeTransferFrom(
                listedItem.seller, msg.sender, listedItem.tokenId, listedItem.quantity, ""
            );
        } else {
            IERC721(listedItem.nftAddress).safeTransferFrom(listedItem.seller, msg.sender, listedItem.tokenId);
        }

        emit ItemBought(
            listedItem.listingId,
            listedItem.nftAddress,
            listedItem.tokenId,
            listedItem.quantity,
            listedItem.price,
            listedItem.feeRate,
            listedItem.seller,
            msg.sender,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId,
            listedItem.desiredQuantity
        );
    }

    // natspec info: the nft owner or authorized operator is able to cancel the listing of their NFT, but also the Governance holder of the marketplace is able to cancel any listing in case there are issues with a listing
    function cancelListing(uint128 listingId) external listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[listingId];
        address diamondOwner = LibDiamond.contractOwner();
        bool isAuthorized;
        if (listedItem.quantity == 0) {
            IERC721 nft = IERC721(listedItem.nftAddress);
            isAuthorized = (
                msg.sender == listedItem.seller || msg.sender == nft.getApproved(listedItem.tokenId)
                    || nft.isApprovedForAll(listedItem.seller, msg.sender)
            );
        } else {
            isAuthorized = (
                msg.sender == listedItem.seller
                    || IERC1155(listedItem.nftAddress).isApprovedForAll(listedItem.seller, msg.sender)
            );
        }
        // allows the diamondOwner to cancel any Listing
        if (!isAuthorized && msg.sender != diamondOwner) {
            revert IdeationMarket__NotAuthorizedToCancel();
        }

        // deactivate the listing // !!! check with cGPT if this is correct instead of deleting the complete struct, this way i have the rest of the data still onchain, just like in the buyitem function
        listedItem.seller = address(0);

        // cleanup the nftTokenToListingIds mapping // !!! let cGPT check this again
        uint128[] storage listingArray = s.nftTokenToListingIds[listedItem.nftAddress][listedItem.tokenId];
        for (uint256 i; i < listingArray.length; ++i) {
            if (listingArray[i] == listingId) {
                listingArray[i] = listingArray[listingArray.length - 1];
                listingArray.pop();
                // !!! should i 'break;' here or is it possible that there might be two listingmappings to delete?
            }
        }

        emit ItemCanceled(listingId, listedItem.nftAddress, listedItem.tokenId, listedItem.seller, msg.sender);
    }

    function updateListing(
        uint128 listingId,
        uint96 newPrice,
        address newDesiredNftAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredQuantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 newQuantity, // >0 for ERC1155, 0 for only ERC721
        bool newBuyerWhitelistEnabled
    ) external listingExists(listingId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[listingId];

        // check if the user is an authorized operator
        if (newQuantity > 0) {
            IERC1155 nft = IERC1155(listedItem.nftAddress);
            // check if the user is authorized
            if (msg.sender != listedItem.seller && !nft.isApprovedForAll(listedItem.seller, msg.sender)) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
        } else {
            IERC721 nft = IERC721(listedItem.nftAddress);
            address tokenHolder = nft.ownerOf(listedItem.tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != nft.getApproved(listedItem.tokenId)
                    && !nft.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
        }

        // check if the Collection is still Whitelisted - even tho it would not have been able to get listed in the first place, if the collection has been revoked in the meantime, updating would cancel the listing
        if (!s.whitelistedCollections[listedItem.nftAddress]) {
            cancelIfNotApproved(listingId);
            return; // !!! does this actually finish the function without doing anything more?
        }

        // Swap-specific check
        if (listedItem.nftAddress == newDesiredNftAddress && listedItem.tokenId == newDesiredTokenId) {
            revert IdeationMarket__NoSwapForSameNft();
        }
        if (newDesiredNftAddress == address(0)) {
            if (newDesiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (newDesiredQuantity != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (newPrice <= 0) revert IdeationMarket__FreeListingsNotSupported();
        } else if (newDesiredQuantity > 0) {
            if (!IERC165(newDesiredNftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__WrongQuantityParameter();
            }
        } else if (newDesiredQuantity == 0) {
            if (!IERC165(newDesiredNftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__WrongQuantityParameter();
            }
        }

        // Use interface check to ensure the MarketPlace is still Approved for transfer and the newQuantity is still valid according to the token Standard ( 0 for ERC721, >0 for ERC1155)
        if (newQuantity > 0) {
            if (listedItem.quantity == 0) {
                revert IdeationMarket__WrongQuantityParameter();
            }
            check1155Approval(listedItem.nftAddress, listedItem.seller);
        } else {
            if (listedItem.quantity > 0) {
                revert IdeationMarket__WrongQuantityParameter();
            }
            check721Approval(listedItem.nftAddress, listedItem.tokenId);
        }

        listedItem.price = newPrice;
        listedItem.desiredNftAddress = newDesiredNftAddress;
        listedItem.desiredTokenId = newDesiredTokenId;
        listedItem.desiredQuantity = newDesiredQuantity;
        listedItem.quantity = newQuantity;
        listedItem.feeRate = s.innovationFee; // note that with updating a listing the up to date innovationFee will be set
        listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled; // other than in the listItem function where the buyerWhitelist gets passed withing creating the listing, when setting the buyerWhitelist from originally false to true through the updateListing function, the whitelist has to get filled through additional calling of the addBuyerWhitelistAddresses function

        emit ItemUpdated(
            listedItem.listingId,
            listedItem.nftAddress,
            listedItem.tokenId,
            newQuantity,
            newPrice,
            listedItem.feeRate,
            listedItem.seller,
            newBuyerWhitelistEnabled,
            newDesiredNftAddress,
            newDesiredTokenId,
            newDesiredQuantity
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

    function check721Approval(address nftAddress, uint256 tokenId) internal view {
        IERC721 nft = IERC721(nftAddress);
        if (!(nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(nft.ownerOf(tokenId), address(this)))) {
            revert IdeationMarket__NotApprovedForMarketplace();
        }
    }

    function check1155Approval(address nftAddress, address nftOwner) internal view {
        if (!IERC1155(nftAddress).isApprovedForAll(nftOwner, address(this))) {
            revert IdeationMarket__NotApprovedForMarketplace();
        }
    }

    function setInnovationFee(uint32 newFee) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 previousFee = s.innovationFee;
        s.innovationFee = newFee;
        emit InnovationFeeUpdated(previousFee, newFee);
    }

    // checks for token contract approval and for collection whitelist
    function cancelIfNotApproved(uint128 listingId) public {
        AppStorage storage s = LibAppStorage.appStorage();
        // Retrieve the current listing. If there's no active listing, exit. We are using this instead of the Modifier in order to safe gas.
        Listing storage listedItem = s.listings[listingId];
        if (listedItem.seller == address(0)) {
            // No listing exists for this NFT, so there's nothing to cancel.
            revert IdeationMarket__NotListed();
        }

        bool approved;

        // !!! add cancel listing if not on collection whitelist anymore - and skip the approval check

        // check approval depending on token type
        if (listedItem.quantity > 0) {
            approved = IERC1155(listedItem.nftAddress).isApprovedForAll(listedItem.seller, address(this));
        } else {
            IERC721 nft = IERC721(listedItem.nftAddress);
            approved = nft.getApproved(listedItem.tokenId) == address(this)
                || nft.isApprovedForAll(listedItem.seller, address(this));
        }

        // If approval is missing, cancel the listing by deleting it from storage.
        if (!approved) {
            // deactivate the listing // !!! check with cGPT if this is correct instead of deleting the complete struct, this way i have the rest of the data still onchain, just like in the buyitem function
            listedItem.seller = address(0);

            // cleanup the nftTokenToListingIds mapping // !!! let cGPT check this again
            uint128[] storage listingArray = s.nftTokenToListingIds[listedItem.nftAddress][listedItem.tokenId];
            for (uint256 i; i < listingArray.length; ++i) {
                if (listingArray[i] == listingId) {
                    listingArray[i] = listingArray[listingArray.length - 1];
                    listingArray.pop();
                    // !!! should i 'break;' here or is it possible that there might be two listingmappings to delete?
                }
            }

            emit ItemCanceledDueToMissingApproval(
                listingId, listedItem.nftAddress, listedItem.tokenId, listedItem.seller, msg.sender
            );
        }
    }
    // find the getter functions in the GetterFacet.sol
}
