// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC165.sol";
import "../interfaces/IERC2981.sol";
import "../interfaces/IERC1155.sol";
import "../interfaces/IBuyerWhitelistFacet.sol";

error IdeationMarket__AlreadyListed(address nftAddress, uint256 tokenId);
error IdeationMarket__NotApprovedForMarketplace();
error IdeationMarket__SellerNotNftOwner(uint256 tokenId, address nftAddress);
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
error IdeationMarket__BuyerNotWhitelisted(address nftAddress, uint256 tokenId, address buyer);
error IdeationMarket__InvalidNoSwapParameters();
error IdeationMarket__SellerInsufficientTokenBalance(uint256 required, uint256 available);
error IdeationMarket__RoyaltyFeeExceedsProceeds();
error IdeationMarket__NotAuthorizedToCancel();
error IdeationMarket__NotOwnerOfDesiredSwap();
error IdeationMarket__TransferFailed();
error IdeationMarket__InsufficientSwapTokenBalance(uint256 required, uint256 available);
error IdeationMarket__WhitelistNotAllowed();
error IdeationMarket__WrongErc1155Holder();
error IdeationMarket__ERC721QuantityMustBe0();
error IdeationMarket__ERC1155QuantityCantBe0();

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
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity,
        uint256 feeRate,
        uint256 quantity,
        bool buyerWhitelistEnabled
    );

    event ItemBought(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        address seller,
        address buyer,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity,
        uint256 feeRate,
        uint256 quantity
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
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity,
        uint256 feeRate,
        uint256 quantity,
        bool buyerWhitelistEnabled
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
        address indexed nftAddress, uint256 indexed tokenId, address indexed royaltyReceiver, uint256 royaltyAmount
    );

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.listings[nftAddress][tokenId].seller == address(0)) revert IdeationMarket__NotListed();
        _;
    }

    // !!! simplify buy requiring the correct erc1155 holder address always when its an erc1155
    modifier isAuthorizedOperator(address nftAddress, uint256 tokenId, address erc1155Holder) {
        if (IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId)) {
            IERC721 nft = IERC721(nftAddress);
            address ownerToken = nft.ownerOf(tokenId);
            if (
                msg.sender != ownerToken && msg.sender != nft.getApproved(tokenId)
                    && !nft.isApprovedForAll(ownerToken, msg.sender)
            ) {
                revert IdeationMarket__NotAuthorizedOperator();
            }
            if (erc1155Holder != address(0)) {
                revert IdeationMarket__WrongErc1155Holder();
            }
        } else if (IERC165(nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
            IERC1155 nft = IERC1155(nftAddress);
            // check if the user is the holder of the Token
            if (nft.balanceOf(msg.sender, tokenId) == 0) {
                // otherwise check if an 'erc1155Holder' has been parsed
                if (erc1155Holder == address(0)) revert IdeationMarket__WrongErc1155Holder();
                // check that this 'erc1155Holder' is really the holder
                if (nft.balanceOf(erc1155Holder, tokenId) == 0) {
                    revert IdeationMarket__SellerNotNftOwner(tokenId, nftAddress);
                }
                // check if the user is authorized
                if (!nft.isApprovedForAll(erc1155Holder, msg.sender)) {
                    revert IdeationMarket__NotAuthorizedOperator();
                }
            } else if (erc1155Holder != address(0) && erc1155Holder != msg.sender) {
                revert IdeationMarket__WrongErc1155Holder();
            }
        } else {
            revert IdeationMarket__NotSupportedTokenStandard();
        }
        _;
    }

    modifier nonReentrant() {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.reentrancyLock) revert IdeationMarket__Reentrant();
        s.reentrancyLock = true;
        _;
        s.reentrancyLock = false;
    }

    modifier onlyWhitelistedCollection(address nftAddress) {
        AppStorage storage s = LibAppStorage.appStorage();
        if (!s.whitelistedCollections[nftAddress]) revert IdeationMarket__CollectionNotWhitelisted(nftAddress);
        _;
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
    ) external isAuthorizedOperator(nftAddress, tokenId, erc1155Holder) onlyWhitelistedCollection(nftAddress) {
        // Prevent relisting an already-listed NFT
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.listings[nftAddress][tokenId].seller != address(0)) {
            revert IdeationMarket__AlreadyListed(nftAddress, tokenId);
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

        // ensure the MarketPlace has been Approved for transfer.
        if (quantity > 0) {
            check1155Approval(nftAddress, seller);
        } else {
            check721Approval(nftAddress, tokenId);
        }

        s.listingIdCounter++;

        uint128 newListingId = s.listingIdCounter;

        s.listingIdToNft[newListingId] = nftAddress;
        s.listingIdToTokenId[newListingId] = tokenId;

        s.listings[nftAddress][tokenId] = Listing({
            listingId: newListingId,
            price: price,
            feeRate: s.innovationFee,
            seller: seller,
            desiredNftAddress: desiredNftAddress,
            desiredTokenId: desiredTokenId,
            desiredQuantity: desiredQuantity,
            quantity: quantity,
            buyerWhitelistEnabled: buyerWhitelistEnabled
        });

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
            price,
            seller,
            desiredNftAddress,
            desiredTokenId,
            desiredQuantity,
            s.innovationFee,
            quantity,
            buyerWhitelistEnabled
        );
    }

    function buyItem(
        address nftAddress,
        uint256 tokenId,
        uint256 expectedQuantity,
        address expectedDesiredNftAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredQuantity,
        address desiredErc1155Holder // if it is a swap listing where the desired nft is an erc1155, the buyer needs to specify the owner of that erc1155, because in case he is not the owner but authorized, the marketplace needs this info to check the approval
    ) external payable nonReentrant isListed(nftAddress, tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];

        // BuyerWhitelist Check
        if (listedItem.buyerWhitelistEnabled) {
            uint128 listingId = listedItem.listingId;
            if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {
                revert IdeationMarket__BuyerNotWhitelisted(nftAddress, tokenId, msg.sender);
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

        if (listedItem.desiredQuantity > 0) {
            if (desiredErc1155Holder == address(0)) revert IdeationMarket__WrongErc1155Holder();
        }

        if (msg.sender == listedItem.seller) {
            revert IdeationMarket__SameBuyerAsSeller();
        }
        // !!! when an authorized operator lists an nft the marketplace will be added as an authorized operator. will that revoke that original operators authorization?
        // Use interface check to ensure the token supports the expected standard. !!! is this really necessary? I mean if they didn't, they could never been listed, right?
        if (listedItem.quantity > 0) {
            if (!IERC165(nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            uint256 balance = IERC1155(nftAddress).balanceOf(listedItem.seller, tokenId);
            if (balance < listedItem.quantity) {
                revert IdeationMarket__SellerInsufficientTokenBalance(listedItem.quantity, balance);
            }
            check1155Approval(nftAddress, listedItem.seller);
        } else {
            if (!IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            address ownerToken = IERC721(nftAddress).ownerOf(tokenId);
            if (ownerToken != listedItem.seller) {
                revert IdeationMarket__SellerNotNftOwner(tokenId, nftAddress);
            }
            check721Approval(nftAddress, tokenId);
        }

        // Calculate the innovation fee based on the listing feeRate (e.g., 2000 for 2% with a denominator of 100000)
        uint256 innovationFee = ((listedItem.price * listedItem.feeRate) / 100000);

        // Seller receives sale price minus the innovation fee
        uint256 sellerProceeds = listedItem.price - innovationFee;

        // in case there is a ERC2981 Royalty defined, Royalties will get deducted from the sellerProceeds aswell
        if (IERC165(nftAddress).supportsInterface(type(IERC2981).interfaceId)) {
            (address royaltyReceiver, uint256 royaltyAmount) =
                IERC2981(nftAddress).royaltyInfo(tokenId, listedItem.price);
            if (royaltyAmount > 0) {
                if (sellerProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();
                sellerProceeds -= royaltyAmount; // NFT royalties get deducted from the sellerProceeds
                s.proceeds[royaltyReceiver] += royaltyAmount; // Update proceeds for the Royalty Receiver
                emit RoyaltyPaid(nftAddress, tokenId, royaltyReceiver, royaltyAmount);
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
                if (swapBalance == 0) revert IdeationMarket__WrongErc1155Holder();
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
                    revert IdeationMarket__NotOwnerOfDesiredSwap();
                }

                // Check approval
                check721Approval(listedItem.desiredNftAddress, listedItem.desiredTokenId);

                // Perform the safe swap transfer buyer to seller.
                desiredNft.safeTransferFrom(msg.sender, listedItem.seller, listedItem.desiredTokenId);
            }

            // in case the desiredNft is listed already, delete that now deprecated listing
            if (s.listings[listedItem.desiredNftAddress][listedItem.desiredTokenId].seller != address(0)) {
                Listing memory desiredItem = s.listings[listedItem.desiredNftAddress][listedItem.desiredTokenId];
                delete (s.listings[listedItem.desiredNftAddress][listedItem.desiredTokenId]);

                emit ItemCanceled(
                    desiredItem.listingId,
                    listedItem.desiredNftAddress,
                    listedItem.desiredTokenId,
                    desiredItem.seller,
                    address(this)
                );
            }
        }

        delete (s.listings[nftAddress][tokenId]);

        // Transfer tokens based on the token standard. !!! in case the transfer wouldn't work, would the proceeds still be paid out?
        if (listedItem.quantity > 0) {
            IERC1155(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId, listedItem.quantity, "");
        } else {
            IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);
        }

        emit ItemBought(
            listedItem.listingId,
            nftAddress,
            tokenId,
            listedItem.price,
            listedItem.seller,
            msg.sender,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId,
            listedItem.desiredQuantity,
            listedItem.feeRate,
            listedItem.quantity
        );
    }

    // natspec info: the nft owner or authorized operator is able to cancel the listing of their NFT, but also the Governance holder of the marketplace is able to cancel any listing in case there are issues with a listing
    function cancelListing(address nftAddress, uint256 tokenId) external isListed(nftAddress, tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        address diamondOwner = LibDiamond.contractOwner();
        bool isAuthorized;
        if (listedItem.quantity == 0) {
            IERC721 nft = IERC721(nftAddress);
            address owner = listedItem.seller;
            isAuthorized = (
                msg.sender == owner || msg.sender == nft.getApproved(tokenId) || nft.isApprovedForAll(owner, msg.sender)
            );
        } else {
            address owner = listedItem.seller;
            isAuthorized = (msg.sender == owner || IERC1155(nftAddress).isApprovedForAll(owner, msg.sender));
        }
        // allows the diamondOwner to cancel any Listing
        if (!isAuthorized && msg.sender != diamondOwner) {
            revert IdeationMarket__NotAuthorizedToCancel();
        }

        delete (s.listings[nftAddress][tokenId]);

        emit ItemCanceled(listedItem.listingId, nftAddress, tokenId, listedItem.seller, msg.sender);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        address erc1155Holder, // !!! this isnt necessary if i take the address from the listedItem.seller
        uint96 newPrice,
        address newDesiredNftAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredQuantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 newQuantity, // >0 for ERC1155, 0 for only ERC721
        bool newBuyerWhitelistEnabled
    )
        external
        isListed(nftAddress, tokenId)
        isAuthorizedOperator(nftAddress, tokenId, erc1155Holder)
        onlyWhitelistedCollection(nftAddress)
    {
        // Swap-specific check
        if (nftAddress == newDesiredNftAddress && tokenId == newDesiredTokenId) {
            revert IdeationMarket__NoSwapForSameNft();
        }
        if (newDesiredNftAddress == address(0)) {
            if (newDesiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (newDesiredQuantity != 0) revert IdeationMarket__InvalidNoSwapParameters();
            if (newPrice <= 0) revert IdeationMarket__FreeListingsNotSupported();
        } else if (newDesiredQuantity > 0) {
            if (!IERC165(newDesiredNftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        } else if (newDesiredQuantity == 0) {
            if (!IERC165(newDesiredNftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        }

        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[nftAddress][tokenId];

        // make sure that the quantity stays 0 for erc721 !!! get this doublechecked by cGPT
        if (listedItem.quantity == 0 && newQuantity != 0) {
            revert IdeationMarket__ERC721QuantityMustBe0();
        }

        // make sure that the quatnity stays >0 for erc1155 !!! get this doublechecked by cGPT
        if (listedItem.quantity != 0 && newQuantity == 0) {
            revert IdeationMarket__ERC1155QuantityCantBe0();
        }

        // if the interacting user is an approved Operator set the token Owner as the seller
        address seller = (erc1155Holder != address(0)) ? erc1155Holder : msg.sender;

        // Use interface check to ensure the token supports the expected standard and the MarketPlace has been Approved for transfer.
        if (newQuantity > 0) {
            check1155Approval(nftAddress, seller);
        } else {
            check721Approval(nftAddress, tokenId);
        }

        listedItem.price = newPrice;
        listedItem.desiredNftAddress = newDesiredNftAddress;
        listedItem.desiredTokenId = newDesiredTokenId;
        listedItem.desiredQuantity = newDesiredQuantity;
        listedItem.quantity = newQuantity;
        listedItem.feeRate = s.innovationFee; // note that with updating a listing the up to date innovationFee will be set
        listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled;

        emit ItemUpdated(
            listedItem.listingId,
            nftAddress,
            tokenId,
            newPrice,
            seller,
            newDesiredNftAddress,
            newDesiredTokenId,
            newDesiredQuantity,
            listedItem.feeRate,
            newQuantity,
            newBuyerWhitelistEnabled
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

    function cancelIfNotApproved(address nftAddress, uint256 tokenId) external {
        AppStorage storage s = LibAppStorage.appStorage();

        // Retrieve the current listing. If there's no active listing, exit. We are using this instead of the Modifier in order to safe gas.
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        if (listedItem.seller == address(0)) {
            // No listing exists for this NFT, so there's nothing to cancel.
            return;
        }

        bool approved;

        // check approval depending on token type
        if (listedItem.quantity >= 0) {
            approved = IERC1155(nftAddress).isApprovedForAll(listedItem.seller, address(this));
        } else {
            IERC721 nft = IERC721(nftAddress);
            approved =
                nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(listedItem.seller, address(this));
        }

        // If approval is missing, cancel the listing by deleting it from storage.
        if (!approved) {
            delete s.listings[nftAddress][tokenId];

            emit ItemCanceledDueToMissingApproval(
                listedItem.listingId, nftAddress, tokenId, listedItem.seller, msg.sender
            );
        }
    }
    // find the getter functions in the GetterFacet.sol
}
