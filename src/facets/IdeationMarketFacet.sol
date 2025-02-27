// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";

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

    // !!!W add NatSpec for every function

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
    )
        external
        // Challenge: Have this contract accept payment in a subset of tokens as well
        // Hint: Use Chainlink Price Feeds to convert the price of the tokens between each other
        // !!!W address tokenPayment - challange: use chainlink pricefeed to let the user decide which currency they want to use - so the user would set his price in eur or usd (or any other available chianlink pricefeed (?) ) and the frontend would always show this currency. when the nft gets bought the buyer would pay in ETH what the useres currency is worth at that time in eth. For that it is also necessary that the withdraw proceeds happens directly so the seller gets the eth asap to convert it back to their currency at a cex of their choice ... additionally i could also integrate an cex api where the seller could register their cexs account at this nft marketplace so that everything happens automatically and the seller gets the money they asked for automatically in their currency. (since it would probaly not be exactly the amount since there are fees and a little time delay from the buyer buying to the seller getting the eur, the marketplace owner should pay up for the difference (but also take if its too much since the price of eth could also go up)) --- NO! https://fravoll.github.io/solidity-patterns/pull_over_push.ht
        isNftOwner(nftAddress, tokenId, msg.sender)
    {
        require(!(nftAddress == desiredNftAddress && tokenId == desiredTokenId), IdeationMarket__NoSwapForSameNft());
        AppStorage storage s = LibAppStorage.appStorage();
        require(s.listings[nftAddress][tokenId].seller == address(0), "IdeationMarket__AlreadyListed");
        // info: approve the NFT Marketplace to transfer the NFT (that way the Owner is keeping the NFT in their wallet until someone bougt it from the marketplace)
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

    // !!!W I think there should be a ~10 minute threshold of people being able to buy a newly listed nft, since it might be that the seller made a mistake and wants to use the update function. so put in something like a counter of blocks mined since the listing of that specific nft to be bought. It should be visible in the frontend aswell tho, that this nft is not yet to be bought but in ~10 minutes.
    function buyItem(address nftAddress, uint256 tokenId) external payable nonReentrant isListed(nftAddress, tokenId) {
        checkApproval(nftAddress, tokenId); // !!!Wt add a test that confirms that the buyItem function fails if the approval has been revoked in the meantime!
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

            // in case the desiredNft is listed already, delete that
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

    function cancelListing(address nftAddress, uint256 tokenId) external isListed(nftAddress, tokenId) {
        // Instantiate the NFT interface to get the current owner.
        IERC721 nft = IERC721(nftAddress);
        address currentOwner = nft.ownerOf(tokenId);
        // Retrieve the diamond (contract) owner.
        address diamondOwner = LibDiamond.contractOwner();

        // Ensure that the caller is either the NFT owner or the diamond owner.
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
        // !!!W this needs to get adjusted for swapping nfts.
        // take notice: when the listing gets updated the ListingId also gets updated!
        address nftAddress,
        uint256 tokenId,
        uint96 newPrice,
        address newDesiredNftAddress,
        uint256 newdesiredTokenId
    ) external isListed(nftAddress, tokenId) isNftOwner(nftAddress, tokenId, msg.sender) {
        require(
            !(nftAddress == newDesiredNftAddress && tokenId == newdesiredTokenId), IdeationMarket__NoSwapForSameNft()
        );
        checkApproval(nftAddress, tokenId);

        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        listedItem.price = newPrice;
        listedItem.desiredNftAddress = newDesiredNftAddress;
        listedItem.desiredTokenId = newdesiredTokenId;
        s.listings[nftAddress][tokenId] = listedItem;
        emit ItemUpdated(
            listedItem.listingId, // !!!Wt test if the listingId stays the same, even if between the listItem creation and the updateListing have been other listings created and deleted
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

    function withdrawProceeds() external payable nonReentrant {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 proceeds = s.proceeds[msg.sender];

        require(proceeds > 0, IdeationMarket__NoProceeds());

        s.proceeds[msg.sender] = 0;
        payable(msg.sender).transfer(proceeds);
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
        // Instantiate the IERC721 interface for the given NFT contract.
        IERC721 nft = IERC721(nftAddress);

        // Get access to the diamond storage.
        AppStorage storage s = LibAppStorage.appStorage();

        // Retrieve the current listing. If there's no active listing, exit. We are using this instead of the Modifier in order to safe gas.
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        if (listedItem.seller == address(0)) {
            // No listing exists for this NFT, so there's nothing to cancel.
            return;
        }

        // Check if the marketplace is still approved to transfer this NFT.
        // We check both individual token approval and operator approval.
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

// !!!W make a nice description/comments/documentation like the zepplin project does.
// !!!W create a good ReadMe.md

// !!!W cGPT mentioned Security tests for edge cases. Just copy the code into cGPT again and ask it for all possible edge cases and how i can write my test for those.
