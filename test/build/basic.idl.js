export const idlFactory = ({ IDL }) => {
  const anon_class_2_1 = IDL.Service({ 'test' : IDL.Func([], [IDL.Nat], []) });
  return anon_class_2_1;
};
export const init = ({ IDL }) => {
  return [IDL.Record({ 'ledgerId' : IDL.Principal })];
};
