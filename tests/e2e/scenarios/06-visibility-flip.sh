# 06: switching public → private → public leaves nothing public behind.
s06() {
  local b; b=$(bucket alpha public)
  use_config alpha "$E2E_DIR/fixtures/alpha-flip-private.yaml"; converge alpha
  assert_eq '[true,true,true,true]' "$(pab "$b")" "after public→private: all Block Public Access flags on"
  assert_eq DenyInsecureTransport "$(policy_sids "$b")" "after public→private: no public statement remains"
  use_config alpha "$E2E_DIR/fixtures/alpha-extra.yaml"; converge alpha
  assert_eq '[true,true,false,false]' "$(pab "$b")" "after private→public: only policy-level blocks lowered"
  assert_eq DenyInsecureTransport,PublicReadObjects "$(policy_sids "$b")" "after private→public: public read restored"
}
scenario 06 "Visibility flip" s06
