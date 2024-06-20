import ICRC "./icrc";

//ILDE added
import SW "mo:stable-write-only"; // ILDE: I have to add mops.toml

module {
    public type Config = {
        var TX_WINDOW : Nat64;
        var PERMITTED_DRIFT : Nat64;
        var FEE : Nat;
        var MINTING_ACCOUNT : ICRC.Account;
    };

    public type Transfer = {
        to : ICRC.Account;
        fee : ?Nat;
        from : ICRC.Account;
        amount : Nat;
    };
    public type Burn = {
        from : ICRC.Account;
        amount: Nat;
    };
    public type Mint = {
        to : ICRC.Account;
        amount : Nat;
    };

    public type Payload = {
        #transfer: Transfer;
        #burn: Burn;
        #mint: Mint;
    };

    public type Action = {
        caller: Principal;
        created_at_time: ?Nat64;
        memo: ?Blob;
        timestamp: Nat64;
        payload: Payload;
    };

    //ILDEBegin
    public type ActionIlde = {
        ts: Nat64;
        created_at_time: ?Nat64; //ILDE: I have added after the discussion with V
        memo: ?Blob; //ILDE: I have added after the discussion with V
        caller: Principal;  //ILDE: I have added after the discussion with V 
        fee: ?Nat;
        payload : {
            #burn : {
                amt: Nat;
                from: [Blob];
            };
            #transfer : {
                to : [Blob];
                from : [Blob];
                amt : Nat;
            };
            #transfer_from : {
                to : [Blob];
                from : [Blob];
                amt : Nat;
            };
            #mint : {
                to : [Blob];
                amt : Nat;
            };
        };
    };

    public type BlockIlde = { 
        #Blob : Blob; 
        #Text : Text; 
        #Nat : Nat;
        #Int : Int;
        #Array : [BlockIlde]; 
        #Map : [(Text, BlockIlde)]; 
    };

    public type ActionIldeWithPhash = ActionIlde and  {phash: Blob} ; // adds a field at the top level
    //ILDEEnd

    public type ActionError = ICRC.TransferError; // can add more error types with 'or'

    public type ActionWithPhash = Action and { phash : Blob };

    //ILDEbegin
    public type ArchiveInitArgs = {
        maxRecords : Nat;
        maxPages : Nat;
        indexType : SW.IndexType;
        firstIndex : Nat;
    };

    public type AddTransactionsResponse = {
        #Full : SW.Stats;
        #ok : SW.Stats;
        #err: Text;
    };

    public type UpdatecontrollerResponse = {
        #ok : Nat;
        #err: Nat;
    };

    /// The type to request a range of transactions from the ledger canister
    public type TransactionRange = {
        start : Nat;
        length : Nat;
    };

    public type Transaction = BlockIlde;

    public type TransactionsResult = {
      blocks: [Transaction];
    };

    public type InitArgs = {
      maxActiveRecords : Nat;
      settleToRecords : Nat;
      maxRecordsInArchiveInstance : Nat;
      maxArchivePages : Nat;
      archiveIndexType : SW.IndexType;
      maxRecordsToArchive : Nat;
      archiveCycles : Nat;
      archiveControllers : ??[Principal];
      supportedBlocks : [BlockIlde];
    };
    
    public type canister_settings = {
        controllers : ?[Principal];
        freezing_threshold : ?Nat;
        memory_allocation : ?Nat;
        compute_allocation : ?Nat;
    };
    
    public type IC = actor {
        update_settings : shared {
            canister_id : Principal;
            settings : canister_settings;
        } -> async ();
    };

    public type BlockType = {
        block_type : Text;
        url : Text;
    };

    public type Stats = {
        localLedgerSize : Nat;
        lastIndex: Nat;
        firstIndex: Nat;
        archives: [(Principal, TransactionRange)];
        supportedBlocks: [BlockType];
        ledgerCanister : ?Principal;
        bCleaning : Bool;
    
        constants : {
        archiveProperties: {
            maxActiveRecords : Nat;
            settleToRecords : Nat;
            maxRecordsInArchiveInstance : Nat;
            maxRecordsToArchive : Nat;
            archiveCycles : Nat;
            archiveControllers : ??[Principal];
        };
        };
    };
    
    public type GetBlocksArgs = [TransactionRange];
    
    public type GetTransactionsResult = {
        // Total number of transactions in the
        // transaction log
        log_length : Nat;        
        blocks : [{ id : Nat; block : BlockIlde }];
        archived_blocks : [ArchivedTransactionResponse];
    };
    public type GetTransactionsFn = shared query ([TransactionRange]) -> async GetTransactionsResult;
    public type ArchivedTransactionResponse = {
        args : [TransactionRange];
        callback : GetTransactionsFn;
    };

    public type GetBlocksResult = GetTransactionsResult;
    
    public type GetArchivesArgs =  {
    // The last archive seen by the client.
    // The Ledger will return archives coming
    // after this one if set, otherwise it
    // will return the first archives.
      from : ?Principal;
    };
    public type GetArchivesResult
    
}