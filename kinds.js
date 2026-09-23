.pragma library
// One icon per Tightbeam decision-request kind, shared by the menu and the
// decision windows so a kind looks the same everywhere. Tightbeam's own kind
// names describe its internals; these describe what each one asks of Mike.
var known = {
  operator: { icon: "󱜸", label: "Agent questions", singular: "agent question",
              hint: "an agent is asking you to choose" },
  effort: { icon: "󰗶", label: "Substrate issues", singular: "substrate issue",
            hint: "Tightbeam flagged an agent that was prodded and produced nothing" }
}

// A kind this plugin has not heard of keeps its raw name and a generic icon.
function info(kind) {
  return known[kind] || { icon: "󰋗", label: String(kind), singular: String(kind),
                          hint: kind + " decision requests" }
}
