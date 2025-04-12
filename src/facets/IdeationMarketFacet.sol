// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC165.sol";
import "../interfaces/IERC2981.sol";
import "../interfaces/IERC1155.sol";

error IdeationMarket__NotApprovedForMarketplace();
error IdeationMarket__NotNftOwner(uint256 tokenId, address nftAddress, address nftOwner);
error IdeationMarket__PriceNotMet(uint256 listingId, uint256 price, uint256 value);
error IdeationMarket__NoProceeds();
error IdeationMarket__SameBuyerAsSeller();
error IdeationMarket__NoSwapForSameNft();
error IdeationMarket__NotSupportedTokenStandard();
error IdeationMarket__NotListed();
error IdeationMarket__Reentrant();
error IdeationMarket__CollectionNotWhitelisted(address nftAddress);
error IdeationMarket__BuyerNotWhitelisted(address nftAddress, uint256 tokenId, address buyer);
error IdeationMarket__InvalidNoSwapTokenId();
error IdeationMarket__InsufficientTokenBalance(uint256 required, uint256 available);
error IdeationMarket__RoyaltyFeeExceedsProceeds();
error IdeationMarket__NotAuthorizedToCancel();
error IdeationMarket__NotOwnerOfDesiredSwap();
error IdeationMarket__MarketplaceNotApprovedForERC1155();
error IdeationMarket__TransferFailed();
error IdeationMarket__InsufficientSwapTokenBalance(uint256 required, uint256 available);

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
     * @param feeRate Fee rate at the time of listing.
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
        uint256 innovationFee,
        uint256 founderFee1,
        uint256 founderFee2,
        uint256 founderFee3,
        uint256 quantity
    );

    event ItemCanceled(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        address seller,
        address triggerdBy
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
        uint256 quantity
    );

    event ProceedsWithdrawn(address indexed withdrawer, uint256 amount);

    event IdeationMarketFeeUpdated(uint256 previousFee, uint256 newFee);

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

    // these are defined in the LibAppStorage.sol
    //     struct Listing {
    //     uint128 listingId;
    //     uint96 price;
    //     uint32 feeRate; // storing the fee at the time of listing
    //     address seller;
    //     address desiredNftAddress; // For swap Listing !=address(0)
    //     uint256 desiredTokenId;
    //     uint256 desiredQuantity; // For swap ERC1155 >1 and for swap ERC721 ==0 or non swap
    //     uint256 quantity; // For ERC1155 >1 and for ERC721 ==0
    //     bool buyerWhitelistEnabled; // true means only whitelisted buyers can purchase.
    // }

    // struct AppStorage {
    //     uint128 listingId;
    //     uint32 ideationMarketFee; // e.g., 2000 = 2% // this is the total fee (excluding gascosts) for each sale, including founderFee and innovationFee
    //     mapping(address => mapping(uint256 => Listing)) listings; // Listings by NFT contract and token ID
    //     mapping(address => uint256) proceeds; // Proceeds by seller address
    //     bool reentrancyLock;
    //     address founder1;
    //     address founder2;
    //     address founder3;
    //     uint32 founder1Ratio; // e.g., 25500 for 25,5% of the total ideationMarketFee
    //     uint32 founder2Ratio; // e.g., 17000 for 17% of the total ideationMarketFee
    //     uint32 founder3Ratio; // e.g., 7500 for 7,5% of the total ideationMarketFee
    //     mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)
    //     address[] whitelistedCollectionsArray; // for lookups
    //     mapping(address => uint256) whitelistedCollectionsIndex; // to make lookups and deletions more efficient
    //     mapping(address => mapping(uint256 => mapping(address => bool))) whitelistedBuyersByNFT; // nftAddress => tokenId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)
    //     uint256 buyerWhitelistMaxBatchSize; // should be
    // }

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

    modifier isNftOwner(address nftAddress, uint256 tokenId, address nftOwner) {
        IERC721 nft = IERC721(nftAddress);
        if (msg.sender != nft.ownerOf(tokenId)) {
            revert IdeationMarket__NotNftOwner(tokenId, nftAddress, nft.ownerOf(tokenId));
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

    modifier onlyWhitelistedBuyer(address nftAddress, uint256 tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[nftAddress][tokenId];
        if (listedItem.buyerWhitelistEnabled) {
            if (!s.whitelistedBuyersByNFT[nftAddress][tokenId][msg.sender]) {
                revert IdeationMarket__BuyerNotWhitelisted(nftAddress, tokenId, msg.sender);
            }
        }
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
        uint96 price,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 desiredQuantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 quantity, // >0 for ERC1155, 0 for only ERC721
        bool buyerWhitelistEnabled
    ) external isNftOwner(nftAddress, tokenId, msg.sender) onlyWhitelistedCollection(nftAddress) {
        // Swap-specific check
        if (nftAddress == desiredNftAddress && tokenId == desiredTokenId) {
            revert IdeationMarket__NoSwapForSameNft();
        }
        if (desiredNftAddress == address(0)) {
            if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapTokenId();
        } else if (desiredNftAddress != address(0) && desiredQuantity > 0) {
            if (!IERC165(desiredNftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        } else if (desiredNftAddress != address(0) && desiredQuantity == 0) {
            if (!IERC165(desiredNftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        } //else: no swap listing

        // Use interface check to ensure the token supports the expected standard and the MarketPlace has been Approved for transfer.
        if (quantity > 0) {
            if (!IERC165(nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            uint256 balance = IERC1155(nftAddress).balanceOf(msg.sender, tokenId);
            if (balance < quantity) revert IdeationMarket__InsufficientTokenBalance(quantity, balance);
            check1155Approval(nftAddress, msg.sender);
        } else {
            if (!IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            if (IERC721(nftAddress).ownerOf(tokenId) != msg.sender) {
                revert IdeationMarket__NotNftOwner(tokenId, nftAddress, IERC721(nftAddress).ownerOf(tokenId));
            }
            checkApproval(nftAddress, tokenId);
        }

        AppStorage storage s = LibAppStorage.appStorage();

        s.listingId++;

        s.listings[nftAddress][tokenId] = Listing({
            listingId: s.listingId,
            price: price,
            feeRate: s.ideationMarketFee,
            seller: msg.sender,
            desiredNftAddress: desiredNftAddress,
            desiredTokenId: desiredTokenId,
            desiredQuantity: desiredQuantity,
            quantity: quantity,
            buyerWhitelistEnabled: buyerWhitelistEnabled
        });

        emit ItemListed(
            s.listingId,
            nftAddress,
            tokenId,
            price,
            msg.sender,
            desiredNftAddress,
            desiredTokenId,
            desiredQuantity,
            s.ideationMarketFee,
            quantity,
            buyerWhitelistEnabled
        );
    }

    function buyItem(address nftAddress, uint256 tokenId)
        external
        payable
        nonReentrant
        isListed(nftAddress, tokenId)
        onlyWhitelistedBuyer(nftAddress, tokenId)
    {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];

        // !!! maybe load all these into memory to safe on storage access?
        // listedItem.price,
        // listedItem.seller,
        // listedItem.desiredNftAddress,
        // listedItem.desiredTokenId,
        // listedItem.desiredQuantity,
        // listedItem.feeRate,

        if (msg.sender == listedItem.seller) {
            revert IdeationMarket__SameBuyerAsSeller();
        }

        if (msg.value < listedItem.price) {
            revert IdeationMarket__PriceNotMet(listedItem.listingId, listedItem.price, msg.value);
        }

        // Use interface check to ensure the token supports the expected standard.
        if (listedItem.quantity > 0) {
            if (!IERC165(nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            uint256 balance = IERC1155(nftAddress).balanceOf(listedItem.seller, tokenId);
            if (balance < listedItem.quantity) {
                revert IdeationMarket__InsufficientTokenBalance(listedItem.quantity, balance);
            }
            check1155Approval(nftAddress, listedItem.seller);
        } else {
            if (!IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            if (IERC721(nftAddress).ownerOf(tokenId) != listedItem.seller) {
                revert IdeationMarket__NotNftOwner(tokenId, nftAddress, IERC721(nftAddress).ownerOf(tokenId));
            }
            checkApproval(nftAddress, tokenId);
        }

        // Calculate the total fee based on the listing feeRate (e.g., 2000 for 2% with a denominator of 100000)
        uint256 totalFee = ((listedItem.price * listedItem.feeRate) / 100000);

        // Calculate each founder's share based on their ratio (ratios should sum to 100)
        uint256 founderFee1Amount = (totalFee * s.founder1Ratio) / 100000;
        uint256 founderFee2Amount = (totalFee * s.founder2Ratio) / 100000;
        uint256 founderFee3Amount = (totalFee * s.founder3Ratio) / 100000;

        // Calculate the innovationFee that goes to the Diamond Owner / DAO Multisig Wallet
        uint256 innovationFee = totalFee - (founderFee1Amount + founderFee2Amount + founderFee3Amount);

        // Seller receives sale price minus the total fee
        uint256 sellerProceeds = listedItem.price - totalFee;

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

        // Update proceeds for the seller, marketplace owner, and each founder

        s.proceeds[listedItem.seller] += sellerProceeds;
        s.proceeds[LibDiamond.contractOwner()] += innovationFee;
        s.proceeds[s.founder1] += founderFee1Amount;
        s.proceeds[s.founder2] += founderFee2Amount;
        s.proceeds[s.founder3] += founderFee3Amount;

        // in case it's a swap listing, send that desired nft (the frontend approves the marketplace for that action beforehand)
        if (listedItem.desiredNftAddress != address(0)) {
            // Detect the desired token's standard using ERC165 interface checks.

            if (listedItem.desiredQuantity > 0) {
                // For ERC1155: Check that buyer holds enough token.
                if (
                    IERC1155(listedItem.desiredNftAddress).balanceOf(msg.sender, listedItem.desiredTokenId)
                        < listedItem.desiredQuantity
                ) {
                    revert IdeationMarket__InsufficientSwapTokenBalance(
                        listedItem.desiredQuantity,
                        IERC1155(listedItem.desiredNftAddress).balanceOf(msg.sender, listedItem.desiredTokenId)
                    );
                }

                // Check approval
                check1155Approval(listedItem.desiredNftAddress, msg.sender);

                // Perform the safe swap transfer buyer to seller.
                IERC1155(listedItem.desiredNftAddress).safeTransferFrom(
                    msg.sender, listedItem.seller, listedItem.desiredTokenId, listedItem.desiredQuantity, ""
                );
            } else {
                IERC721 desiredNft = IERC721(listedItem.desiredNftAddress); // !!! this sturcture safes a bit of gas because the listedItem.desiredNFTAddress gets loaded into memory so it doesnt have to be loaded from storage so often - i should do that everywhere applicable - but doublcheck with cGPT!
                // For ERC721: Check ownership.
                if (desiredNft.ownerOf(listedItem.desiredTokenId) != msg.sender) {
                    revert IdeationMarket__NotOwnerOfDesiredSwap();
                }

                // Check approval
                checkApproval(listedItem.desiredNftAddress, listedItem.desiredTokenId);

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
                    address(this) // !!! check if this is the address of the cancelation triggering entity
                );
            }
        }

        delete (s.listings[nftAddress][tokenId]);

        /// !!! does this also set the seller parameter to 0?

        // Transfer tokens based on the token standard.
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
            innovationFee,
            founderFee1Amount,
            founderFee2Amount,
            founderFee3Amount,
            listedItem.quantity
        );
    }

    // natspec info: the nft owner is able to cancel the listing of their NFT, but also the Governance holder of the marketplace is able to cancel any listing in case there are issues with a listing
    function cancelListing(address nftAddress, uint256 tokenId) external isListed(nftAddress, tokenId) {
        IERC721 nft = IERC721(nftAddress);
        address currentOwner = nft.ownerOf(tokenId);
        address diamondOwner = LibDiamond.contractOwner();

        if (msg.sender != currentOwner && msg.sender != diamondOwner) revert IdeationMarket__NotAuthorizedToCancel();

        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        delete (s.listings[nftAddress][tokenId]);

        emit ItemCanceled(listedItem.listingId, nftAddress, tokenId, listedItem.seller, msg.sender);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint96 newPrice,
        address newDesiredNftAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredQuantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap
        uint256 newQuantity // >0 for ERC1155, 0 for only ERC721
    )
        external
        isListed(nftAddress, tokenId)
        isNftOwner(nftAddress, tokenId, msg.sender)
        onlyWhitelistedCollection(nftAddress)
    {
        // Swap-specific check
        if (nftAddress == newDesiredNftAddress && tokenId == newDesiredTokenId) {
            revert IdeationMarket__NoSwapForSameNft();
        }
        if (newDesiredNftAddress == address(0)) {
            if (newDesiredTokenId != 0) revert IdeationMarket__InvalidNoSwapTokenId();
        } else if (newDesiredQuantity > 0) {
            if (!IERC165(newDesiredNftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        } else {
            if (!IERC165(newDesiredNftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
        }
        //else: no swap listing

        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[nftAddress][tokenId];

        // Use interface check to ensure the token supports the expected standard and the MarketPlace has been Approved for transfer.
        if (newQuantity > 0) {
            // Assume this is an ERC1155 listing.
            if (!IERC165(nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            uint256 balance = IERC1155(nftAddress).balanceOf(msg.sender, tokenId);
            if (balance < newQuantity) revert IdeationMarket__InsufficientTokenBalance(newQuantity, balance);
            check1155Approval(nftAddress, msg.sender);
        } else {
            // For quantity==0, assume an ERC721 token.
            if (!IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId)) {
                revert IdeationMarket__NotSupportedTokenStandard();
            }
            if (IERC721(nftAddress).ownerOf(tokenId) != msg.sender) {
                revert IdeationMarket__NotNftOwner(tokenId, nftAddress, IERC721(nftAddress).ownerOf(tokenId));
            }
            checkApproval(nftAddress, tokenId);
        }

        listedItem.price = newPrice;
        listedItem.desiredNftAddress = newDesiredNftAddress;
        listedItem.desiredTokenId = newDesiredTokenId;
        listedItem.desiredQuantity = newDesiredQuantity;
        listedItem.quantity = newQuantity;
        listedItem.feeRate = s.ideationMarketFee;

        emit ItemUpdated(
            listedItem.listingId,
            nftAddress,
            tokenId,
            newPrice,
            msg.sender,
            newDesiredNftAddress,
            newDesiredTokenId,
            newDesiredQuantity,
            listedItem.feeRate,
            newQuantity
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

    function checkApproval(address nftAddress, uint256 tokenId) internal view {
        IERC721 nft = IERC721(nftAddress);
        if (!(nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(nft.ownerOf(tokenId), address(this)))) {
            revert IdeationMarket__NotApprovedForMarketplace();
        }
    }

    function check1155Approval(address nftAddress, address nftOwner) internal view {
        if (!IERC1155(nftAddress).isApprovedForAll(nftOwner, address(this))) {
            revert IdeationMarket__MarketplaceNotApprovedForERC1155();
        }
    }

    function setTotalFee(uint32 fee) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 previousFee = s.ideationMarketFee;
        s.ideationMarketFee = fee;
        emit IdeationMarketFeeUpdated(previousFee, fee);
    }

    function setFounder1(address _founder1, uint8 _ratio) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        s.founder1 = _founder1;
        s.founder1Ratio = _ratio;
    }

    function setFounder2(address _founder2, uint8 _ratio) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        s.founder2 = _founder2;
        s.founder2Ratio = _ratio;
    }

    function setFounder3(address _founder3, uint8 _ratio) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        s.founder3 = _founder3;
        s.founder3Ratio = _ratio;
    }

    function cancelIfNotApproved(address nftAddress, uint256 tokenId) external {
        IERC721 nft = IERC721(nftAddress);
        AppStorage storage s = LibAppStorage.appStorage();

        // Retrieve the current listing. If there's no active listing, exit. We are using this instead of the Modifier in order to safe gas.
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        if (listedItem.seller == address(0)) {
            // No listing exists for this NFT, so there's nothing to cancel.
            return;
        }

        // Check if the marketplace is still approved to transfer this NFT.
        if (nft.getApproved(tokenId) != address(this) && !nft.isApprovedForAll(nft.ownerOf(tokenId), address(this))) {
            // Approval is missing; cancel the listing by deleting it from storage.
            delete s.listings[nftAddress][tokenId];

            emit ItemCanceledDueToMissingApproval(
                listedItem.listingId, nftAddress, tokenId, listedItem.seller, msg.sender
            );
        }
    }
    // find getter functions in the GetterFacet.sol
}
