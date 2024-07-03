export const idlFactory = ({ IDL }) => {
  const _anon_class_13_1 = IDL.Service({
    'test' : IDL.Func([], [IDL.Nat], []),
  });
  return _anon_class_13_1;
};
export const init = ({ IDL }) => {
  return [IDL.Record({ 'ledgerId' : IDL.Principal })];
};
