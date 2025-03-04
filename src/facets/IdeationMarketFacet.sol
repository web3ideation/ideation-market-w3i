// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC165.sol";

error IdeationMarket__NotApprovedForMarketplace();
error IdeationMarket__NotNftOwner(uint256 tokenId, address nftAddress, address nftOwner);
error IdeationMarket__PriceNotMet(uint256 listingId, uint256 price, uint256 value);
error IdeationMarket__NoProceeds();
error IdeationMarket__SameBuyerAsSeller();
error IdeationMarket__NoSwapForSameNft();

contract IdeationMarketFacet {
    event ItemListed(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        bool isListed,
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 feeRate
    );

    event ItemBought(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        bool isListed,
        uint256 price,
        address seller,
        address buyer,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 feeRate
    );

    event ItemCanceled(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        bool isListed,
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId,
        address triggerdBy
    );

    event ItemUpdated(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        bool isListed,
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId,
        uint256 feeRate
    );

    event ProceedsWithdrawn(address indexed withdrawer, uint256 amount);

    event IdeationMarketFeeUpdated(uint256 previousFee, uint256 newFee);

    // Event emitted when a listing is canceled due to revoked approval.
    event ItemCanceledDueToMissingApproval(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        bool isListed,
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId,
        address triggeredBy
    );

    // these are defined in the LibAppStorage.sol
    // struct Listing {
    //      uint128 listingId;
    //      uint96 price;
    //      uint32 feeRate; // storing the fee at the time of listing
    //      address seller;
    //      address desiredNftAddress;
    //      uint256 desiredTokenId;
    // }

    // these are defined in the LibAppStorage.sol
    // uint128 listingId;
    // uint32 ideationMarketFee; // e.g., 100 = 0.1%
    // mapping(address => mapping(uint256 => Listing)) listings; // Listings by NFT contract and token ID
    // mapping(address => uint256) proceeds; // Proceeds by seller address
    // bool reentrancyLock;

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        require(s.listings[nftAddress][tokenId].seller != address(0), "IdeationMarket__NotListed");
        _;
    }

    modifier isNftOwner(address nftAddress, uint256 tokenId, address nftOwner) {
        IERC721 nft = IERC721(nftAddress);
        require(
            msg.sender == nft.ownerOf(tokenId), IdeationMarket__NotNftOwner(tokenId, nftAddress, nft.ownerOf(tokenId))
        );
        _;
    }

    modifier nonReentrant() {
        AppStorage storage s = LibAppStorage.appStorage();
        require(!s.reentrancyLock, "ReentrancyGuard: reentrant call");
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
        uint96 price,
        address desiredNftAddress,
        uint256 desiredTokenId
    ) external isNftOwner(nftAddress, tokenId, msg.sender) {
        require(IERC165(nftAddress).supportsInterface(0x80ac58cd), "Provided contract is not ERC721");
        require(!(nftAddress == desiredNftAddress && tokenId == desiredTokenId), IdeationMarket__NoSwapForSameNft());
        if (desiredNftAddress != address(0)) {
            require(IERC165(desiredNftAddress).supportsInterface(0x80ac58cd), "Provided contract is not ERC721");
        }
        AppStorage storage s = LibAppStorage.appStorage();
        require(s.listings[nftAddress][tokenId].seller == address(0), "IdeationMarket__AlreadyListed");
        checkApproval(nftAddress, tokenId);
        s.listingId++;
        s.listings[nftAddress][tokenId] =
            Listing(s.listingId, price, s.ideationMarketFee, msg.sender, desiredNftAddress, desiredTokenId);
        emit ItemListed(
            s.listingId,
            nftAddress,
            tokenId,
            true,
            price,
            msg.sender,
            desiredNftAddress,
            desiredTokenId,
            s.ideationMarketFee
        );
    }

    function buyItem(address nftAddress, uint256 tokenId) external payable nonReentrant isListed(nftAddress, tokenId) {
        checkApproval(nftAddress, tokenId);
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];

        require(
            listedItem.seller == IERC721(nftAddress).ownerOf(tokenId),
            IdeationMarket__NotNftOwner(tokenId, nftAddress, IERC721(nftAddress).ownerOf(tokenId))
        );

        require(msg.sender != listedItem.seller, IdeationMarket__SameBuyerAsSeller());

        require(
            msg.value >= listedItem.price,
            IdeationMarket__PriceNotMet(listedItem.listingId, listedItem.price, msg.value)
        );

        uint256 fee = ((listedItem.price * listedItem.feeRate) / 100000);
        uint256 newProceeds = listedItem.price - fee;
        s.proceeds[listedItem.seller] += newProceeds;
        s.proceeds[LibDiamond.contractOwner()] += fee;

        // in case it's a swap listing, send that desired nft (the frontend approves the marketplace for that action beforehand)
        if (listedItem.desiredNftAddress != address(0)) {
            IERC721 desiredNft = IERC721(listedItem.desiredNftAddress);
            require(
                desiredNft.ownerOf(listedItem.desiredTokenId) == msg.sender, "You don't own the desired NFT for swap"
            );
            checkApproval(listedItem.desiredNftAddress, listedItem.desiredTokenId);

            desiredNft.safeTransferFrom(msg.sender, listedItem.seller, listedItem.desiredTokenId);

            // in case the desiredNft is listed already, delete that now deprecated listing
            if (s.listings[listedItem.desiredNftAddress][listedItem.desiredTokenId].seller != address(0)) {
                Listing memory desiredItem = s.listings[listedItem.desiredNftAddress][listedItem.desiredTokenId];
                delete (s.listings[listedItem.desiredNftAddress][listedItem.desiredTokenId]);

                emit ItemCanceled(
                    desiredItem.listingId,
                    listedItem.desiredNftAddress,
                    listedItem.desiredTokenId,
                    false,
                    desiredItem.price,
                    desiredItem.seller,
                    desiredItem.desiredNftAddress,
                    desiredItem.desiredTokenId,
                    address(this)
                );
            }
        }

        delete (s.listings[nftAddress][tokenId]);

        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);

        emit ItemBought(
            listedItem.listingId,
            nftAddress,
            tokenId,
            false,
            listedItem.price,
            listedItem.seller,
            msg.sender,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId,
            listedItem.feeRate
        );
    }

    // natspec info: the nft owner is able to cancel the listing of their NFT, but also the Governance holder of the marketplace is able to cancel any listing in case there are issues with a listing
    function cancelListing(address nftAddress, uint256 tokenId) external isListed(nftAddress, tokenId) {
        IERC721 nft = IERC721(nftAddress);
        address currentOwner = nft.ownerOf(tokenId);
        address diamondOwner = LibDiamond.contractOwner();

        require(
            msg.sender == currentOwner || msg.sender == diamondOwner, "cancelListing: Not authorized to cancel listing"
        );
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        delete (s.listings[nftAddress][tokenId]);

        emit ItemCanceled(
            listedItem.listingId,
            nftAddress,
            tokenId,
            false,
            listedItem.price,
            listedItem.seller,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId,
            msg.sender
        );
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint96 newPrice,
        address newDesiredNftAddress,
        uint256 newDesiredTokenId
    ) external isListed(nftAddress, tokenId) isNftOwner(nftAddress, tokenId, msg.sender) {
        require(
            !(nftAddress == newDesiredNftAddress && tokenId == newDesiredTokenId), IdeationMarket__NoSwapForSameNft()
        );
        if (newDesiredNftAddress == address(0)) {
            require(newDesiredTokenId == 0, "If no swap address, tokenId must be 0");
        } else {
            require(IERC165(newDesiredNftAddress).supportsInterface(0x80ac58cd), "Provided contract is not ERC721");
        }

        checkApproval(nftAddress, tokenId);
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[nftAddress][tokenId];
        listedItem.price = newPrice;
        listedItem.desiredNftAddress = newDesiredNftAddress;
        listedItem.desiredTokenId = newDesiredTokenId;
        listedItem.feeRate = s.ideationMarketFee;
        emit ItemUpdated(
            listedItem.listingId,
            nftAddress,
            tokenId,
            true,
            listedItem.price,
            msg.sender,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId,
            listedItem.feeRate
        );
    }

    function withdrawProceeds() external nonReentrant {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 proceeds = s.proceeds[msg.sender];

        require(proceeds > 0, IdeationMarket__NoProceeds());

        s.proceeds[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: proceeds}("");
        require(success, "Transfer of proceeds failed");
        emit ProceedsWithdrawn(msg.sender, proceeds);
    }

    function checkApproval(address nftAddress, uint256 tokenId) internal view {
        IERC721 nft = IERC721(nftAddress);
        require(
            nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(nft.ownerOf(tokenId), address(this)),
            IdeationMarket__NotApprovedForMarketplace()
        );
    }

    function setFee(uint32 fee) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 previousFee = s.ideationMarketFee;
        s.ideationMarketFee = fee;
        emit IdeationMarketFeeUpdated(previousFee, fee);
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
                listedItem.listingId,
                nftAddress,
                tokenId,
                false,
                listedItem.price,
                listedItem.seller,
                listedItem.desiredNftAddress,
                listedItem.desiredTokenId,
                msg.sender // caller who triggered the cancellation
            );
        }
    }

    //////////////////////
    // getter Functions //
    //////////////////////

    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.listings[nftAddress][tokenId];
    }

    function getProceeds(address seller) external view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.proceeds[seller];
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
