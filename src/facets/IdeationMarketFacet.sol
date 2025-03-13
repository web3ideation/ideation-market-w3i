// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC165.sol";
import "../interfaces/IERC2981.sol";

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
        uint256 feeRate,
        uint256 innovationFee,
        uint256 founderFee1,
        uint256 founderFee2,
        uint256 founderFee3
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

    event RoyaltyPaid(
        address indexed nftAddress, uint256 indexed tokenId, address indexed royaltyReceiver, uint256 royaltyAmount
    );

    // these are defined in the LibAppStorage.sol
    // struct Listing {
    //      uint128 listingId;
    //      uint96 price;
    //      uint32 feeRate; // storing the fee at the time of listing
    //      address seller;
    //      address desiredNftAddress;
    //      uint256 desiredTokenId;
    //      TokenStandard tokenStandard;
    //      uint256 quantity;            // For ERC1155 (should be 1 for ERC721/ERC4907)
    //      uint256 rentalExpiry;        // For ERC4907 tokens (0 if not a rental)
    // }

    // these are defined in the LibAppStorage.sol
    // uint128 listingId;
    // uint32 ideationMarketFee; // e.g., 2000 = 2% // this is the total fee (excluding gascosts) for each sale, including founderFee and innovationFee
    // mapping(address => mapping(uint256 => Listing)) listings; // Listings by NFT contract and token ID
    // mapping(address => uint256) proceeds; // Proceeds by seller address
    // bool reentrancyLock;
    // address founder1;
    // address founder2;
    // address founder3;
    // uint32 founder1Ratio; // e.g., 25500 for 25,5% of the total ideationMarketFee
    // uint32 founder2Ratio; // e.g., 17000 for 17% of the total ideationMarketFee
    // uint32 founder3Ratio; // e.g., 7500 for 7,5% of the total ideationMarketFee
    // mapping(address => bool) whitelistedCollections;
    // address[] whitelistedCollectionsArray;
    // mapping(address => uint256) whitelistedCollectionsIndex;

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

    modifier onlyWhitelistedCollection(address nftAddress) {
        AppStorage storage s = LibAppStorage.appStorage();
        require(s.whitelistedCollections[nftAddress], "Collection not whitelisted");
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
        uint256 desiredTokenId
    ) external isNftOwner(nftAddress, tokenId, msg.sender) onlyWhitelistedCollection(nftAddress) {
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
        if (IERC165(nftAddress).supportsInterface(0x2a55205a)) {
            (address royaltyReceiver, uint256 royaltyAmount) =
                IERC2981(nftAddress).royaltyInfo(tokenId, listedItem.price);
            if (royaltyAmount > 0) {
                require(sellerProceeds >= royaltyAmount, "Royalty fee exceeds proceeds");
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
            listedItem.feeRate,
            innovationFee,
            founderFee1Amount,
            founderFee2Amount,
            founderFee3Amount
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
    )
        external
        isListed(nftAddress, tokenId)
        isNftOwner(nftAddress, tokenId, msg.sender)
        onlyWhitelistedCollection(nftAddress)
    {
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
