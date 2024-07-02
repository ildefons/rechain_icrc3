export const idlFactory = ({ IDL }) => {
  const anon_class_13_1 = IDL.Service({});
  return anon_class_13_1;
};
export const init = ({ IDL }) => {
  return [IDL.Record({ 'ledgerId' : IDL.Principal })];
};
