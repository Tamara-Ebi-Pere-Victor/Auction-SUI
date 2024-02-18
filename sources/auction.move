module auction::example {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};


    const EAuctionEnded : u64 = 0;
    const EAuctionNotEnded: u64 = 1;
    const EBidTooLow : u64 = 2;
    const ENoBidsMade : u64 = 3;
    const ENotCreator: u64 = 4;
    const EWrongAuction: u64 = 5;
    const EWinnerCannotGetRefund: u64 = 6;

    // owned object item
    struct Item has key, store{
        id: UID,
        name: vector<u8>,
        desc: vector<u8>,
        start_price: u64,
        final_price: u64,
    }

    // shared object to track bids
    struct Auction has key {
        id: UID,
        item_id: ID,
        bid_balance: Balance<SUI>,
        starting_bid: u64,
        highest_bid: u64,
        highest_bidder: Option<address>,
        auction_state: u8, // 0 - can bid, 1 - cannot bid
        auction_ends: u64
    }   

    // owned object that bidders use to get a refund
    struct Receipt has key, store {
        id: UID,
        auction_id: ID,
        amount: u64,
    } 

    public fun list_item(name: vector<u8>, desc: vector<u8>, start_price: u64, clock: &Clock, ctx: &mut TxContext): Item {
        // create item object, this object is an owned object 
        let item = Item {
            id: object::new(ctx),
            name,
            desc,
            start_price,
            final_price: 0,
        };

        // get item id
        let item_id = object::uid_to_inner(&item.id);

        // get current_time : auction duration is set to 20 ticks;
        let current_time = clock::timestamp_ms(clock);
        let end_time = current_time + 20;
        
        // create item auction, which is shared so can be accessed by anyone
        let auction = Auction {
            id: object::new(ctx),
            item_id,
            bid_balance: balance::zero(),
            starting_bid: start_price,
            highest_bid: start_price,
            highest_bidder: option::none(),
            auction_state: 0,
            auction_ends: end_time
        };

        // make item auction shared
        transfer::share_object(auction);

        // return item
        item
    }

    public fun bid(auction: &mut Auction, amount: Coin<SUI>, clock: &Clock, ctx: &mut TxContext): Receipt {
        // check that auction has not ended
        let current_time = clock::timestamp_ms(clock);
        assert!(auction.auction_ends > current_time, EAuctionEnded);

        // check that auction state is 0
        assert!(auction.auction_state == 0, EAuctionEnded);

        // check that the current bid is higher than auction highest bid
        let bid_amount = coin::value(&amount);
        assert!(bid_amount > auction.highest_bid, EBidTooLow);

        // add the amount to the bid balance
        let coin_balance = coin::into_balance(amount);
        balance::join(&mut auction.bid_balance, coin_balance);

        // set new bid as the highest bid and bidder the highest bidder
        auction.highest_bid = bid_amount;
        auction.highest_bidder = option::some(tx_context::sender(ctx));

        // generate receipt for refund
        let auction_id = object::uid_to_inner(&auction.id);

        let receipt = Receipt {
            id: object::new(ctx),
            auction_id,
            amount: bid_amount,
        };

        receipt
    }

    // only item creator can call this
    public fun settle_bid(item: Item, auction: &mut Auction, clock: &Clock, ctx: &mut TxContext): Coin<SUI> {
        // check that only item creator can call
        assert!(&auction.item_id == object::uid_as_inner(&item.id), ENotCreator);
        
        // check that auction has ended
        let current_time = clock::timestamp_ms(clock);
        assert!(auction.auction_ends < current_time, EAuctionNotEnded);

        // check that auction state is 0
        assert!(auction.auction_state == 0, EAuctionEnded);

        // check that highest bid is not the same as starting big
        assert!(auction.highest_bid > auction.starting_bid, ENoBidsMade);

        // get the coin from the bid balance
        let final_price = coin::take(&mut auction.bid_balance, auction.highest_bid, ctx);

        // update the item final price
        item.final_price = auction.highest_bid;

        // transfer the item to highest bidder
        let recipient = option::extract<address>(&mut auction.highest_bidder);

        transfer::public_transfer(item, recipient);

        // update auction as ended
        auction.auction_state = 1;

        final_price
    }


    // allows bidders to get refund after auction ends
    public fun get_refund(auction: &mut Auction, receipt: Receipt, ctx: &mut TxContext): Coin<SUI> {
        // destructure receipt
        let Receipt {id, amount: amount, auction_id: auction_id} = receipt;

        // check receipt is sent with right auction
        assert!(&auction_id == object::uid_as_inner(&auction.id), EWrongAuction);

        // check that txn context
        assert!(!option::contains(&auction.highest_bidder, &tx_context::sender(ctx)), EWinnerCannotGetRefund);

        // check that auction state is ended
        assert!(auction.auction_state == 1, EAuctionNotEnded);

        // delete refund object
        object::delete(id);

        // get the coin from the bid balance
        let refund = coin::take(&mut auction.bid_balance, amount, ctx);

        refund
    }

    #[test_only] use sui::test_scenario as ts;
    #[test_only] const SELLER: address = @0x1;
    #[test_only] const Bidder1: address = @0xA;
    #[test_only] const Bidder2: address = @0xB;

    #[test]
    fun test_auction(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // Seller lists item
        {   
            ts::next_tx(&mut ts, SELLER);
            
            // set the item parameters
            let name = b"antique pocket watch";
            let desc = b"1988 old man edition watch";
            let start_price: u64 = 5; // 5 SUI
            
            // create item
            let item = list_item(name, desc, start_price, &clock, ts::ctx(&mut ts));
            
            // transfer item to owner
            transfer::public_transfer(item, SELLER);
        };

        // First Bid
        {
            ts::next_tx(&mut ts, Bidder1);
            
            // get auction
            let auction = ts::take_shared(&ts);

            // mint test tokens
            let coin = coin::mint_for_testing<SUI>(8, ts::ctx(&mut ts));
            
            // call bid and generate receipt
            let receipt = bid(&mut auction, coin, &clock, ts::ctx(&mut ts));

            // transfer receipt to Bidder1
            transfer::public_transfer(receipt, Bidder1);

            ts::return_shared(auction);
        };

        // Second Bid 
        {
            ts::next_tx(&mut ts, Bidder2);
            
            // get auction
            let auction = ts::take_shared(&ts);

            // mint test tokens
            let coin = coin::mint_for_testing<SUI>(14, ts::ctx(&mut ts));
            
            // call bid and generate receipt
            let receipt = bid(&mut auction, coin, &clock, ts::ctx(&mut ts));

            // transfer receipt to Bidder2
            transfer::public_transfer(receipt, Bidder2);

            ts::return_shared(auction);

        };

        // Max out clock and settle bid
        {
            ts::next_tx(&mut ts, SELLER);

            // increment clock to auction end time
            clock::increment_for_testing(&mut clock, 21);

            // get auction
            let auction: Auction = ts::take_shared(&ts);
            
            // get item
            let item: Item = ts::take_from_sender(&ts);


            // call bid and transfer item to highest bidder
            let bid_amount = settle_bid(item, &mut auction, &clock, ts::ctx(&mut ts));

            // transfer bid amount to seller
            transfer::public_transfer(bid_amount, SELLER);

            ts::return_shared(auction);
        };

        // Bidder1 gets a refund as bidder2 is the highest bidder
        {
            ts::next_tx(&mut ts, Bidder1);

            // get auction
            let auction: Auction = ts::take_shared(&ts);
            
            // get receipt
            let receipt: Receipt = ts::take_from_sender(&ts);

            // get refund coin
            let refund = get_refund(&mut auction, receipt, ts::ctx(&mut ts));

            // transfer bid amount to seller
            transfer::public_transfer(refund, Bidder1);

            ts::return_shared(auction);
        };

        clock::destroy_for_testing(clock);
        ts::end(ts);
    }

    #[test]
    #[expected_failure]
    fun test_auction_should_reject_bids_if_auction_time_ended(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // Seller lists item
        {   
            ts::next_tx(&mut ts, SELLER);
            
            // set the item parameters
            let name = b"antique pocket watch";
            let desc = b"1988 old man edition watch";
            let start_price: u64 = 5; // 5 SUI
            
            // create item
            let item = list_item(name, desc, start_price, &clock, ts::ctx(&mut ts));
            
            // transfer item to owner
            transfer::public_transfer(item, SELLER);
        };

        // First bid should fail as it's lower
        {
            ts::next_tx(&mut ts, Bidder1);

            // increment clock to auction end time
            clock::increment_for_testing(&mut clock, 21);
            
            // get auction
            let auction = ts::take_shared(&ts);

            // mint test tokens
            let coin = coin::mint_for_testing<SUI>(4, ts::ctx(&mut ts));
            
            // call bid and generate receipt
            let receipt = bid(&mut auction, coin, &clock, ts::ctx(&mut ts));

            // transfer receipt to Bidder1
            transfer::public_transfer(receipt, Bidder1);

            ts::return_shared(auction);
        };

        clock::destroy_for_testing(clock);
        ts::end(ts);
    }

    #[test]
    #[expected_failure]
    fun test_auction_should_fail_if_bidder_tries_to_bid_lower_than_starting_price(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // Seller lists item
        {   
            ts::next_tx(&mut ts, SELLER);
            
            // set the item parameters
            let name = b"antique pocket watch";
            let desc = b"1988 old man edition watch";
            let start_price: u64 = 5; // 5 SUI
            
            // create item
            let item = list_item(name, desc, start_price, &clock, ts::ctx(&mut ts));
            
            // transfer item to owner
            transfer::public_transfer(item, SELLER);
        };

        // First bid should fail as it's lower
        {
            ts::next_tx(&mut ts, Bidder1);
            
            // get auction
            let auction = ts::take_shared(&ts);

            // mint test tokens
            let coin = coin::mint_for_testing<SUI>(4, ts::ctx(&mut ts));
            
            // call bid and generate receipt
            let receipt = bid(&mut auction, coin, &clock, ts::ctx(&mut ts));

            // transfer receipt to Bidder1
            transfer::public_transfer(receipt, Bidder1);

            ts::return_shared(auction);
        };

        clock::destroy_for_testing(clock);
        ts::end(ts);
    }


    #[test]
    #[expected_failure]
    fun test_auction_should_fail_if_winner_tries_to_get_refund(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // Seller lists item
        {   
            ts::next_tx(&mut ts, SELLER);
            
            // set the item parameters
            let name = b"antique pocket watch";
            let desc = b"1988 old man edition watch";
            let start_price: u64 = 5; // 5 SUI
            
            // create item
            let item = list_item(name, desc, start_price, &clock, ts::ctx(&mut ts));
            
            // transfer item to owner
            transfer::public_transfer(item, SELLER);
        };

        // First Bid
        {
            ts::next_tx(&mut ts, Bidder1);
            
            // get auction
            let auction = ts::take_shared(&ts);

            // mint test tokens
            let coin = coin::mint_for_testing<SUI>(8, ts::ctx(&mut ts));
            
            // call bid and generate receipt
            let receipt = bid(&mut auction, coin, &clock, ts::ctx(&mut ts));

            // transfer receipt to Bidder1
            transfer::public_transfer(receipt, Bidder1);

            ts::return_shared(auction);
        };

        // Second Bid 
        {
            ts::next_tx(&mut ts, Bidder2);
            
            // get auction
            let auction = ts::take_shared(&ts);

            // mint test tokens
            let coin = coin::mint_for_testing<SUI>(14, ts::ctx(&mut ts));
            
            // call bid and generate receipt
            let receipt = bid(&mut auction, coin, &clock, ts::ctx(&mut ts));

            // transfer receipt to Bidder2
            transfer::public_transfer(receipt, Bidder2);

            ts::return_shared(auction);

        };

        // Max out clock and settle bid
        {
            ts::next_tx(&mut ts, SELLER);

            // increment clock to auction end time
            clock::increment_for_testing(&mut clock, 21);

            // get auction
            let auction: Auction = ts::take_shared(&ts);
            
            // get item
            let item: Item = ts::take_from_sender(&ts);


            // call bid and transfer item to highest bidder
            let bid_amount = settle_bid(item, &mut auction, &clock, ts::ctx(&mut ts));

            // transfer bid amount to seller
            transfer::public_transfer(bid_amount, SELLER);

            ts::return_shared(auction);
        };

        // Bidder2 to get refund, should fail.
        {
            ts::next_tx(&mut ts, Bidder2);

            // get auction
            let auction: Auction = ts::take_shared(&ts);
            
            // get receipt
            let receipt: Receipt = ts::take_from_sender(&ts);

            // get refund coin
            let refund = get_refund(&mut auction, receipt, ts::ctx(&mut ts));

            // transfer bid amount to seller
            transfer::public_transfer(refund, Bidder2);

            ts::return_shared(auction);
        };

        clock::destroy_for_testing(clock);
        ts::end(ts);
    }

}