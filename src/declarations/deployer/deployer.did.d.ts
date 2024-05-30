import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface Account {
  'owner' : Principal,
  'subaccount' : [] | [Uint8Array | number[]],
}
export interface Action {
  'ts' : bigint,
  'fee' : [] | [bigint],
  'payload' : {
      'burn' : { 'to' : Array<Uint8Array | number[]>, 'amt' : bigint }
    } |
    { 'mint' : { 'to' : Array<Uint8Array | number[]>, 'amt' : bigint } } |
    {
      'transfer_from' : {
        'to' : Array<Uint8Array | number[]>,
        'amt' : bigint,
        'from' : Array<Uint8Array | number[]>,
      }
    } |
    {
      'transfer' : {
        'to' : Array<Uint8Array | number[]>,
        'amt' : bigint,
        'from' : Array<Uint8Array | number[]>,
      }
    },
}
export interface ArchivedRange {
  'callback' : [Principal, string],
  'start' : bigint,
  'length' : bigint,
}
export type Block = [BlockSchemaId, Uint8Array | number[]];
export type BlockSchemaId = string;
export interface GetBlocksRequest { 'start' : bigint, 'length' : bigint }
export interface GetTransactionsResponse {
  'first_index' : bigint,
  'log_length' : bigint,
  'transactions' : Array<Block>,
  'archived_transactions' : Array<ArchivedRange>,
}
export type Result = { 'Ok' : bigint } |
  { 'Err' : TransferError };
export interface TransactionRange { 'transactions' : Array<Block> }
export interface TransferArg {
  'to' : Account,
  'fee' : [] | [bigint],
  'memo' : [] | [Uint8Array | number[]],
  'from_subaccount' : [] | [Uint8Array | number[]],
  'created_at_time' : [] | [bigint],
  'amount' : bigint,
}
export type TransferError = {
    'GenericError' : { 'message' : string, 'error_code' : bigint }
  } |
  { 'TemporarilyUnavailable' : null } |
  { 'BadBurn' : { 'min_burn_amount' : bigint } } |
  { 'Duplicate' : { 'duplicate_of' : bigint } } |
  { 'BadFee' : { 'expected_fee' : bigint } } |
  { 'CreatedInFuture' : { 'ledger_time' : bigint } } |
  { 'TooOld' : null } |
  { 'InsufficientFunds' : { 'balance' : bigint } };
export interface _SERVICE {
  'add_record' : ActorMethod<[Action], bigint>,
  'batch_transfer' : ActorMethod<[Array<TransferArg>], Array<Result>>,
  'get_transactions' : ActorMethod<[GetBlocksRequest], GetTransactionsResponse>,
  'icrc1_balance_of' : ActorMethod<[Account], bigint>,
  'icrc1_transfer' : ActorMethod<[TransferArg], Result>,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
