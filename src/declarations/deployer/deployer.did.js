export const idlFactory = ({ IDL }) => {
  const Action = IDL.Record({
    'ts' : IDL.Nat,
    'fee' : IDL.Opt(IDL.Nat),
    'payload' : IDL.Variant({
      'burn' : IDL.Record({
        'to' : IDL.Vec(IDL.Vec(IDL.Nat8)),
        'amt' : IDL.Nat,
      }),
      'mint' : IDL.Record({
        'to' : IDL.Vec(IDL.Vec(IDL.Nat8)),
        'amt' : IDL.Nat,
      }),
      'transfer_from' : IDL.Record({
        'to' : IDL.Vec(IDL.Vec(IDL.Nat8)),
        'amt' : IDL.Nat,
        'from' : IDL.Vec(IDL.Vec(IDL.Nat8)),
      }),
      'transfer' : IDL.Record({
        'to' : IDL.Vec(IDL.Vec(IDL.Nat8)),
        'amt' : IDL.Nat,
        'from' : IDL.Vec(IDL.Vec(IDL.Nat8)),
      }),
    }),
  });
  const Account = IDL.Record({
    'owner' : IDL.Principal,
    'subaccount' : IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  const TransferArg = IDL.Record({
    'to' : Account,
    'fee' : IDL.Opt(IDL.Nat),
    'memo' : IDL.Opt(IDL.Vec(IDL.Nat8)),
    'from_subaccount' : IDL.Opt(IDL.Vec(IDL.Nat8)),
    'created_at_time' : IDL.Opt(IDL.Nat64),
    'amount' : IDL.Nat,
  });
  const TransferError = IDL.Variant({
    'GenericError' : IDL.Record({
      'message' : IDL.Text,
      'error_code' : IDL.Nat,
    }),
    'TemporarilyUnavailable' : IDL.Null,
    'BadBurn' : IDL.Record({ 'min_burn_amount' : IDL.Nat }),
    'Duplicate' : IDL.Record({ 'duplicate_of' : IDL.Nat }),
    'BadFee' : IDL.Record({ 'expected_fee' : IDL.Nat }),
    'CreatedInFuture' : IDL.Record({ 'ledger_time' : IDL.Nat64 }),
    'TooOld' : IDL.Null,
    'InsufficientFunds' : IDL.Record({ 'balance' : IDL.Nat }),
  });
  const Result = IDL.Variant({ 'Ok' : IDL.Nat, 'Err' : TransferError });
  const GetBlocksRequest = IDL.Record({
    'start' : IDL.Nat,
    'length' : IDL.Nat,
  });
  const BlockSchemaId = IDL.Text;
  const Block = IDL.Tuple(BlockSchemaId, IDL.Vec(IDL.Nat8));
  const TransactionRange = IDL.Record({ 'transactions' : IDL.Vec(Block) });
  const ArchivedRange = IDL.Record({
    'callback' : IDL.Func([GetBlocksRequest], [TransactionRange], ['query']),
    'start' : IDL.Nat,
    'length' : IDL.Nat,
  });
  const GetTransactionsResponse = IDL.Record({
    'first_index' : IDL.Nat,
    'log_length' : IDL.Nat,
    'transactions' : IDL.Vec(Block),
    'archived_transactions' : IDL.Vec(ArchivedRange),
  });
  return IDL.Service({
    'add_record' : IDL.Func([Action], [IDL.Nat], []),
    'batch_transfer' : IDL.Func([IDL.Vec(TransferArg)], [IDL.Vec(Result)], []),
    'get_transactions' : IDL.Func(
        [GetBlocksRequest],
        [GetTransactionsResponse],
        ['query'],
      ),
    'icrc1_balance_of' : IDL.Func([Account], [IDL.Nat], ['query']),
    'icrc1_transfer' : IDL.Func([TransferArg], [Result], []),
  });
};
export const init = ({ IDL }) => { return []; };
