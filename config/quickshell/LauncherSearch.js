// Launcher search: multi-term fuzzy matching over desktop entries.
//
// Ported from Omarchy Quattro's AppSearch.js (MIT,
// https://github.com/basecamp/omarchy) and simplified: the word/acronym
// splitting, the per-term matching and the scoring ladder are theirs; this
// copy adds usage-count ranking on top (fuzzel-style most-recently-used
// ordering for the empty query, and a tiebreaker under a query).
//
// QML's JS engine runs this as classic script, so it stays ES5 — like the
// rest of this shell's JavaScript.

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entryDetail(entry) {
  return String((entry && entry.genericName) || (entry && entry.comment) || "")
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function")
      return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

// Everything an entry should be findable by.
function entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id].join(" ").toLowerCase()
}

// "Google Chrome" and "org.gnome.Nautilus" both split into matchable words.
function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

// "gc" finds "Google Chrome". Short queries only — matching long ones by
// acronym turns up noise faster than value.
function entryAcronym(entry) {
  var values = words([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function termMatches(entry, term) {
  if (!term) return true

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)

  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true

  return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

// Every whitespace-separated term must match somewhere ("term fire" finds
// "Firefox Terminal" as well as "Terminal Emulator"? no — but "fire term"
// does, which single-term matching wouldn't).
function allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return false
  }
  return true
}

// -1 means "does not match". Otherwise higher is better; the ladder mirrors
// Omarchy's: name-prefix beats id-prefix beats substring beats acronym.
function fuzzyScore(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

  return 4000 - name.length
}

// Visible rows for the current query: noDisplay entries and unnamed entries
// stay out, matches score in, then score → usage → name decides the order.
// The empty query scores everything 0, so usage and then the alphabet order
// the list — the "menu" state the launcher opens into.
function sortedEntries(values, query, usageCounts) {
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    var name = entryName(entry)
    if (!name) continue
    var score = fuzzyScore(entry, q)
    if (score < 0) continue
    var uses = usageCounts ? Number(usageCounts[String(entry.id)] || 0) : 0
    rows.push({
      entryId: String(entry.id),
      label: name,
      icon: String(entry.icon || ""),
      detail: entryDetail(entry),
      score: score,
      uses: uses
    })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.uses !== b.uses) return b.uses - a.uses
    var keyA = a.label.toLowerCase()
    var keyB = b.label.toLowerCase()
    if (keyA < keyB) return -1
    if (keyA > keyB) return 1
    return 0
  })

  return rows
}
