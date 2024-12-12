// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";

error IdeationMarket__NotApprovedForMarketplace();
error IdeationMarket__NotNftOwner(uint256 tokenId, address nftAddress, address nftOwner); // !!!W all those arguments might be too much unnecessary information. does it safe gas or sth if i leave it out?
error IdeationMarket__PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error IdeationMarket__NoProceeds();
error IdeationMarket__TransferFailed(); // !!!W is this even necessary? i think it reverts on its own when it fails, right? If it is necessary maybe add the error message that is given by the transfer function

contract IdeationMarketFacet {
    // struct Listing {
    //     uint256 listingId; // *** I want that every Listing has a uinque Lising Number, just like in the real world :)
    //     // !!!W then it would make sense to just always let the functions also work if only the listingId is given in the args, also the errors should only return the listingId and not the nftAddress and tokenId
    //     uint256 price;
    //     address seller;
    //     address desiredNftAddress; // Desired NFTs for swap !!!W find a way to have multiple desiredNftAddresses ( and / or ) - maybe by using an array here(?)
    //     uint256 desiredTokenId; // Desired token IDs for swap !!!W find a way to have multiple desiredNftAddresses ( and / or ) - maybe by using an array here(?)
    // } // *** also find a way to have the seller list their nft for swap WITH additional ETH. so that they can say i want my 1ETH worth NFT to be swapped against this specific NFT AND 0.3 ETH.

    // !!!W maybe I should change the isListed to something like status where i have an enum with options listed, updated, canceled, bought, swapped, etc. and then i can have a function that returns all the listings of a specific status. that would be a nice feature for the frontend. But more importantly i can use this for thegraph to feed the frontend this this specific information.
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
    // *** should i add the seller to this event? Yes, did it.
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

    event FeeUpdated(uint256 previousFee, uint256 newFee);

    // !!!W the listing mapping could be aswell be defined by listing ID instead of NFT. That would be a more streamlined experience
    // !!!W add that all the info of the listings mapping can be returned when calling a getter function with the listingId as the parameter/argument
    // NFT Contract address -> NFT TokenID -> Listing
    // mapping(address => mapping(uint256 => Listing)) private listings;

    // seller address -> amount earned
    // mapping(address => uint256) private proceeds;

    // address private owner; // !!!W If the diamond contract doesnt take care of that: Make sure to be give the possibility to transfer ownership

    // uint256 public ideationMarketFee; // ***W this should also be adaptable -> variable to be set by contract owner // W*** add to the proceeds mapping the contract owner so there would be logged how much fee there is to be deducted, and with this the owner should be able to withdraw the fees - i guess i need to initilize the contract owner through the constructor then // !!!W add a way to send all eth that are in this contract to the companys wallet (or is that already there just by being the owner of the cotnract?) // !!!W when a listing is set the fee should stick to it, meaning that if the fee changes in the meantime, that listing still has the old fee. Do that by adding fee to the listing and using that for the proceeds.

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner(); // Ensure caller is the diamond owner
        _;
    }

    modifier notListed(address nftAddress, uint256 tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        require(s.listings[nftAddress][tokenId].seller == address(0), "IdeationMarket__AlreadyListed");
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        require(s.listings[nftAddress][tokenId].seller != address(0), "IdeationMarket__NotListed");
        _;
    }

    // !!!W isnt that a modifier only owner which i inherited from open zeplin of something?? then i could just use that instead of making my own
    modifier isNftOwner(
        address nftAddress,
        uint256 tokenId,
        address nftOwner // !!!W rename this to nftOwner - bc it uses the same name as the contractowner variable
    ) {
        IERC721 nft = IERC721(nftAddress);
        if (msg.sender != nft.ownerOf(tokenId)) {
            revert IdeationMarket__NotNftOwner(tokenId, nftAddress, nft.ownerOf(tokenId));
        } // !!!W make this a require statement instead of an if statement(?)
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

    // !!!W add a catch for if the user wants to list the same nft as they set as their desiredNftAddress and desiredTokenId. that should not be possible.
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
        notListed(nftAddress, tokenId)
        isNftOwner(nftAddress, tokenId, msg.sender)
    {
        // !!!W since the already listed / not listed modifiers dont use the price anymore but the seller, i dont need to check if the price is above 0 anymore. -> delte this check
        // require(
        //     price > 0 || desiredNftAddress != address(0),
        //     "IdeationMarket__PriceMustBeAboveZeroOrNoDesiredNftGiven"
        // );

        // !!!W I need to add a check that the user doesnt try to swap list agains the same nft they are listing. so if the desiredNftAddress and desiredTokenId are the same as the nftAddress and tokenId, it should revert.

        AppStorage storage s = LibAppStorage.appStorage();

        require(!(nftAddress == desiredNftAddress && tokenId == desiredTokenId), "IdeationMarket__NoSwapForSameNft");

        // info: approve the NFT Marketplace to transfer the NFT (that way the Owner is keeping the NFT in their wallet until someone bougt it from the marketplace)
        checkApproval(nftAddress, tokenId);
        s.listingId++;
        s.listings[nftAddress][tokenId] = Listing(s.listingId, price, msg.sender, desiredNftAddress, desiredTokenId);
        emit ItemListed(s.listingId, nftAddress, tokenId, true, price, msg.sender, desiredNftAddress, desiredTokenId);

        // !!!W is there a way to listen to the BasicNft event for if the approval has been revoked, to then cancel the listing automatically?
    }

    function checkApproval(address nftAddress, uint256 tokenId) internal view {
        // !!!W would it make sense to have this being a modifier?
        IERC721 nft = IERC721(nftAddress);
        if (nft.getApproved(tokenId) != address(this)) {
            revert IdeationMarket__NotApprovedForMarketplace();
        } // !!!W make this a require statement instead of an if statement(?)
    }

    // !!!W The seller of an item shouldnt be able to buy it, make a revert for that
    // !!!W I think there should be a ~10 minute threshold of people being able to buy a newly listed nft, since it might be that the seller made a mistake and wants to use the update function. so put in something like a counter of blocks mined since the listing of that specific nft to be bought. It should be visible in the frontend aswell tho, that this nft is not yet to be bought but in ~10 minutes.
    function buyItem(
        address nftAddress, // !!!W should i rather work with the listingId of the struct? that seems more streamlined...
        uint256 tokenId
    ) external payable nonReentrant isListed(nftAddress, tokenId) {
        AppStorage storage s = LibAppStorage.appStorage();
        // !!!W if two users call the function concurrently the second user will be blocked. what happens then? is there a way to not even have the user notice that and just try again?
        // checkApproval(nftAddress, tokenId); // !!!W I want to check if the ideationMarket still has the rights to transfer the nft when it is about to be bought. but i probably have to change this function sincec this time its the buyer calling it, not the seller so it needs to get the sellers addres via the listingStruct// !!!W add a test that confirms that the buyItem function fails if the approval has been revoked in the meantime!
        Listing memory listedItem = s.listings[nftAddress][tokenId];

        if (msg.value < listedItem.price) {
            revert IdeationMarket__PriceNotMet(nftAddress, tokenId, listedItem.price); // !!!W I think it would be good to add msg.value as well so its visible how much eth has actually been tried to transfer, since i guess there are gas costs and stuff...
                // !!!W i could also do this with `require(msg.value == listedItem.price, "Incorrect Ether sent");` - is this better? like safer and or gas efficient?
                // !!!W make this a require statement instead of an if statement(?)
        } else {
            // !!!W this else keyword is not necessary, should i keep it? does it make a gas difference?
            uint256 fee = ((listedItem.price * s.ideationMarketFee) / 100000);
            uint256 newProceeds = listedItem.price - fee;
            s.proceeds[listedItem.seller] += newProceeds;
            s.proceeds[LibDiamond.contractOwner()] += fee; // !!!W check if this  is the correct way of logging/collecting the marketplace fee (including the calculation of the variable 'fee')
            if (listedItem.desiredNftAddress != address(0)) {
                IERC721 desiredNft = IERC721(listedItem.desiredNftAddress);
                require( // !!!W should i have this as a modifier just like the isOwner one i use for the listItem?
                desiredNft.ownerOf(listedItem.desiredTokenId) == msg.sender, "You don't own the desired NFT for swap");
                checkApproval(listedItem.desiredNftAddress, listedItem.desiredTokenId); // !!!W this is a quick fix. cGPT said there was an issue about the approval.

                // Swap the NFTs
                desiredNft.safeTransferFrom(msg.sender, listedItem.seller, listedItem.desiredTokenId);
                // !!!W In case the swapped nft had been actively listed at the time, that listing has to get canceled
                // !!!W when implementing the swap + eth option, i need to have the proceeds here aswell. - i think i do already at the top...
            } // !!!W make this a require statement instead of an if statement(?)
            // maybe its safer to not use else but start a new if with `if (!listedItem.isForSwap) {`

            delete (s.listings[nftAddress][tokenId]); // W!!! cGPT said bv of reentrancy attacks i need to move this here instead of after the nft transfer. check if it still works. check if i should also consider that before transfering the swap NFT. // !!!W Ask cGPT again what else i need to do to be fully reentrancy attack proof

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
    }

    function cancelListing(address nftAddress, uint256 tokenId)
        external
        isListed(nftAddress, tokenId)
        isNftOwner(nftAddress, tokenId, msg.sender)
    {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing memory listedItem = s.listings[nftAddress][tokenId]; // what happens to this memory variable after the struct in the mapping has been deleted and after the function has been executed? does it get deleted automatically?
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
        // *** patrick didnt make sure that the updated price would be above 0 in his contract
        // !!!W since the already listed / not listed modifiers dont use the price anymore but the seller, i dont need to check if the price is above 0 anymore. -> delte this check
        // require(
        //     newPrice > 0 || newDesiredNftAddress != address(0),
        //     "IdeationMarket__PriceMustBeAboveZeroOrNoDesiredNftGiven"
        // );

        AppStorage storage s = LibAppStorage.appStorage();

        require(
            !(nftAddress == newDesiredNftAddress && tokenId == newdesiredTokenId), "IdeationMarket__NoSwapForSameNft"
        );

        checkApproval(nftAddress, tokenId); // *** patrick didnt check if the approval is still given in his contract
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

    // to try out the ReentrancyAttack.sol,  comment out the `nonReentrant` , move the `proceeds[msg.sender] = 0;` to after the ETH transfer and change the `payable(msg.sender).transfer(proceeds);` to `(bool success, ) = payable(msg.sender).call{value: proceeds, gas: 30000000}("");` because Hardhat has an issue estimating the gas for the receive fallback function... The Original should work on the testnet, tho! !!!W Try on the testnet if reentrancy attack is possible
    function withdrawProceeds() external payable nonReentrant {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 proceeds = s.proceeds[msg.sender];
        if (proceeds <= 0) {
            revert IdeationMarket__NoProceeds();
        } // !!!W make this a require statement instead of an if statement(?)
        s.proceeds[msg.sender] = 0;
        payable(msg.sender).transfer(proceeds); // *** I'm using this instead of Patricks (bool success, ) = payable(msg.sender).call{value: proceeds}(""); require(success, "IdeationMarket__TransferFailed");`bc mine reverts on its own when it doesnt succeed, and therby I consider it better!
            // should this function also emit an event? just for being able to track when somebody withdrew?
            // !!!W throw an event!
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

    function getNextListingId() external view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.listingId; // *** With this function people can find out what the next Listing Id would be
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
// !!!W test if the approval works as a separate function
// !!!W test if the listingId starts with 1 and than counts up for every time the listItem function has been called
// !!!W how do I actually test this while programming? do i have to write the deploy script already? or is there a way to use the hh console to test on the fly?

// Create a decentralized NFT Marketplace:
// !!!W 0.1. `approve`: approve the smartcontract to transfer the NFT
// 1. `listItem`: List NFTs on the marketplace (/)
// 2. `buyItem`: Buy NFTs
// 3. `cancelItem`: Cancel a listing
// 4. `updateListing`: to update the price
// 5. `withdrawproceeds`: Withdraw payment for my bought NFTs

// !!!W understand when to use the memory keyword, for example for strings and for structs
// !!!W make a nice description/comments/documentation like the zepplin project does.
// !!!W create a good ReadMe.md
// !!!W how do I give myself the option to update this code once it is deployed?
// !!!W set it up that I get 0.1% of all proceeds of every sucessfull(!) sale

// !!!W how can i see emited events on hardhat local host?

// !!!W Partner would like a function that you can swap nfts directly, so you offer yournfts against another specific nft, or multiple?

// !!!W cGPT mentioned Security tests for edge cases. Just copy the code into cGPT again and ask it for all possible edge cases and how i can write my test for those.
