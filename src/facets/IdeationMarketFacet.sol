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
        uint256 desiredTokenId
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
        uint256 desiredTokenId
    );

    event ItemCanceled(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        bool isListed,
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId
    );

    event ItemUpdated(
        uint256 indexed listingId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        bool isListed,
        uint256 price,
        address seller,
        address desiredNftAddress,
        uint256 desiredTokenId
    );

    event ProceedsWithdrawn(address indexed withdrawer, uint256 amount);

    event FeeUpdated(uint256 previousFee, uint256 newFee);

    // these are defined in the LibAppStorage.sol
    // struct Listing {
    //     uint256 listingId;
    //     uint256 price;
    //     address seller;
    //     address desiredNftAddress; // Desired NFTs for swap !!!W find a way to have multiple desiredNftAddresses ( and / or ) - maybe by using an array here(?)
    //     uint256 desiredTokenId; // Desired token IDs for swap !!!W find a way to have multiple desiredNftAddresses ( and / or ) - maybe by using an array here(?)
    // }

    // !!!W the listing mapping could be aswell be defined by listing ID instead of NFT. That would be a more streamlined experience
    // !!!W add that all the info of the listings mapping can be returned when calling a getter function with the listingId as the parameter/argument

    // these are defined in the LibAppStorage.sol
    // uint256 listingId;
    // uint256 ideationMarketFee; // !!!W when a listing is set the fee should stick to it, meaning that if the fee changes in the meantime, that listing still has the old fee. Do that by adding fee to the listing and using that for the proceeds.
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
        uint256 price,
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
        s.listings[nftAddress][tokenId] = Listing(s.listingId, price, msg.sender, desiredNftAddress, desiredTokenId);
        emit ItemListed(s.listingId, nftAddress, tokenId, true, price, msg.sender, desiredNftAddress, desiredTokenId);

        // !!!W is there a way to listen to the BasicNft event for if the approval has been revoked, to then cancel the listing automatically?
    }

    // !!!W I think there should be a ~10 minute threshold of people being able to buy a newly listed nft, since it might be that the seller made a mistake and wants to use the update function. so put in something like a counter of blocks mined since the listing of that specific nft to be bought. It should be visible in the frontend aswell tho, that this nft is not yet to be bought but in ~10 minutes.
    function buyItem(address nftAddress, uint256 tokenId) external payable nonReentrant isListed(nftAddress, tokenId) {
        checkApproval(nftAddress, tokenId); // !!!W add a test that confirms that the buyItem function fails if the approval has been revoked in the meantime!
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];

        require(msg.sender != listedItem.seller, IdeationMarket__SameBuyerAsSeller());

        require(
            msg.value >= listedItem.price,
            IdeationMarket__PriceNotMet(listedItem.listingId, listedItem.price, msg.value)
        );

        uint256 fee = ((listedItem.price * s.ideationMarketFee) / 100000);
        uint256 newProceeds = listedItem.price - fee;
        s.proceeds[listedItem.seller] += newProceeds;
        s.proceeds[LibDiamond.contractOwner()] += fee; // !!!W check if this  is the correct way of logging/collecting the marketplace fee (including the calculation of the variable 'fee')
        if (listedItem.desiredNftAddress != address(0)) {
            IERC721 desiredNft = IERC721(listedItem.desiredNftAddress);
            require(
                desiredNft.ownerOf(listedItem.desiredTokenId) == msg.sender, "You don't own the desired NFT for swap"
            );
            checkApproval(listedItem.desiredNftAddress, listedItem.desiredTokenId); // !!!W this is a quick fix. cGPT said there was an issue about the approval.

            // Swap the NFTs
            desiredNft.safeTransferFrom(msg.sender, listedItem.seller, listedItem.desiredTokenId);

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
                    desiredItem.desiredTokenId
                );
            }
            // !!!W when implementing the swap + eth option, i need to have the proceeds here aswell. - i think i do already at the top...
        }

        delete (s.listings[nftAddress][tokenId]);

        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId); // !!!W this needs an revert catch thingy bc if it fails to transfer the nft, for example because the approval has been revoked, the whole function has to be reverted.

        emit ItemBought(
            listedItem.listingId,
            nftAddress,
            tokenId,
            false,
            listedItem.price,
            listedItem.seller,
            msg.sender,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId
        ); // !!!W Patrick said that the event emitted is technically not save from reantrancy attacks. figure out how and why and make it safe.
    }

    function cancelListing(address nftAddress, uint256 tokenId)
        external
        isListed(nftAddress, tokenId)
        isNftOwner(nftAddress, tokenId, msg.sender)
    {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId];
        delete (s.listings[nftAddress][tokenId]);

        emit ItemCanceled(
            listedItem.listingId,
            nftAddress,
            tokenId,
            false,
            listedItem.price,
            msg.sender,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId
        );
        // nft = IERC721(nftAddress); nft.approve(address(0), tokenId); // !!!W patrick didnt revoke the approval in his contract -> I guess bc its not possible. bc that call can only come from the owner or from the approved for all, while this call here is coming from the contract which is not. But I think it would make sense if the address that is approved would be able to revoke its onw approval, check out why it is not!
    }

    function updateListing(
        // !!!W this needs to get adjusted for swapping nfts.
        // take notice: when the listing gets updated the ListingId also gets updated!
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice,
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
            listedItem.listingId, // !!!W test if the listingId stays the same, even if between the listItem creation and the updateListing have been other listings created and deleted
            nftAddress,
            tokenId,
            true,
            listedItem.price,
            msg.sender,
            listedItem.desiredNftAddress,
            listedItem.desiredTokenId
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
        require(nft.getApproved(tokenId) == address(this), IdeationMarket__NotApprovedForMarketplace());
    }

    function setFee(uint256 fee) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 previousFee = s.ideationMarketFee;
        s.ideationMarketFee = fee;
        emit FeeUpdated(previousFee, fee);
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
// !!!W test if the approval works as a separate function
// !!!W test if the listingId starts with 1 and than counts up for every time the listItem function has been called

// Create a decentralized NFT Marketplace:
// !!!W 0.1. `approve`: approve the smartcontract to transfer the NFT
// 1. `listItem`: List NFTs on the marketplace (/)
// 2. `buyItem`: Buy NFTs
// 3. `cancelItem`: Cancel a listing
// 4. `updateListing`: to update the price
// 5. `withdrawproceeds`: Withdraw payment for my bought NFTs

// !!!W make a nice description/comments/documentation like the zepplin project does.
// !!!W create a good ReadMe.md

// !!!W cGPT mentioned Security tests for edge cases. Just copy the code into cGPT again and ask it for all possible edge cases and how i can write my test for those.
