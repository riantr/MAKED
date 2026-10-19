# Mutation check for the loop engine.
#
# Green tests are not evidence. Each entry deliberately breaks one behaviour
# and asserts the suite goes red.
#
#   .\tools\mutate-loop.ps1
#
# Run from anywhere; the repo root is derived from this script's own path.
#
# Files are patched and restored byte-exactly (UTF-8, no BOM, LF preserved) so
# the repo is unchanged whichever way this script exits.
#
# Two traps this script already hit, both of which look like a weak test and
# are not:
#
#   - An anchor that does not occur in the file. `String::Replace` then does
#     nothing, the suite stays green, and the mutation is reported as
#     SURVIVED. Anchors are checked and a miss is an ERROR.
#   - A single-quoted PowerShell string containing `` `" ``. The backtick is
#     literal there, so the anchor silently never matches. Quote anchors that
#     contain `"` with double quotes instead.

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

# --- mutations ------------------------------------------------------------
# name; file; old text; new text
$mutations = @(
  # The regression this whole exercise exists for. Re-introducing a
  # semantically-chosen slot per domain must turn the suite red -- and it
  # reproduces the exact bug: 5 anchors, 5 slots, all Block.
  #
  # The mapping used to live in `loop.mbt`; it lives in `model.mbt` now,
  # because the model is what the loop asks. The guard follows the code.
  @{
    name = 'drive_slot reverts to a hard-coded semantic mapping'
    file = 'backend/model.mbt'
    old  = @'
pub fn Model::drive_slot(self : Model, from : String) -> String? {
  let moving = []
'@
    new  = @'
pub fn Model::drive_slot(self : Model, from : String) -> String? {
  if from == "standing" {
    return Some("cobeing")
  }
  if from == "encounter" {
    return Some("feedback")
  }
  if from == "honor" {
    return Some("unveil")
  }
  if from == "evil" {
    return Some("hold")
  }
  if from == "cultivation" {
    return Some("orientation")
  }
  let moving = []
'@
  },
  # exitable_slots is the authority for what is drivable at all. A model file
  # does not have to write a rule for every (position, slot) pair, and where
  # it does not, the model must report no way out rather than offer a slot it
  # has no rule for. The built-in model defines all 272 pairs, so this is
  # only observable in a model that does not -- which is exactly the point.
  @{
    name = 'exitable_slots claims every slot works everywhere'
    file = 'backend/model.mbt'
    old  = '      None => ()
    }'
    new  = '      None => usable.push(slot.id)
    }'
  },
  # Preferring a real move over a self-edge.
  @{
    name = 'drive_slot ignores Moved and takes the first slot'
    file = 'backend/model.mbt'
    old  = @'
  if moving.length() > 0 {
    Some(moving[0])
  } else if staying.length() > 0 {
    Some(staying[0])
  } else {
    None
  }
'@
    new  = @'
  if staying.length() > 0 {
    Some(staying[0])
  } else if moving.length() > 0 {
    Some(moving[0])
  } else {
    None
  }
'@
  },
  # A position with no edge must stay a gap. The built-in model has none --
  # all 34 positions have at least one exitable slot -- but a model file
  # written by somebody else can, and `model_test.mbt` has one. So this is a
  # real guard now rather than an expected-equivalent: it is killed by the
  # model that has a genuinely dead position.
  @{
    name = 'drive_slot invents a slot when nothing is exitable'
    file = 'backend/model.mbt'
    old  = @'
  if moving.length() > 0 {
    Some(moving[0])
  } else if staying.length() > 0 {
    Some(staying[0])
  } else {
    None
  }
'@
    new  = @'
  if moving.length() > 0 {
    Some(moving[0])
  } else if staying.length() > 0 {
    Some(staying[0])
  } else {
    Some("act")
  }
'@
  },
  # The status must report the real position, not the static anchor.
  @{
    name = 'to_json reports the anchor instead of the real position'
    file = 'backend/loop.mbt'
    # The map is keyed by domain id, so the lookup carries the id with it.
    # An earlier anchor read `self.domain_states[self.current]`, which stopped
    # matching when the key became the id -- the mutation then never applied
    # and the guard was testing air.
    old  = '  let current_ds = self.domain_states[self.current.id]
  let current_pos = current_ds.position'
    new  = '  let current_pos = self.current.position()'
  },
  # Block must not advance the cursor.
  @{
    name = 'cursor advances even when the step was blocked'
    file = 'backend/loop.mbt'
    # Anchored on ASCII only. An earlier version embedded a CJK label and
    # never matched: PowerShell read this script as a non-UTF-8 codepage, so the
    # literal was mangled before the comparison ran. The file is written
    # UTF-8 without BOM and still trips this, so anchors avoid CJK entirely.
    old  = 'let next_domain = if effect.moved() && !blocked {'
    new  = 'let next_domain = if false ||'
  },
  # The drive slot in the status must come from the table. Pinned by ASCII
  # only -- the replacement needs no CJK, so this anchor stays readable and
  # immune to the encoding trouble below.
  @{
    name = 'status hard-codes a drive slot again'
    file = 'backend/loop.mbt'
    old  = @'
    "drive_slot": match drive_slot(current_pos) {
      Some(slot) => model.slot_designation(slot)
      None => ""
    },
'@
    new  = @'
    "drive_slot": "Co-being",
'@
  },
  # open_slots is the replacement for the hard-coded list; it must be the
  # table's answer, not all eight slots.
  @{
    name = 'open_slots lists all eight slots'
    file = 'backend/loop.mbt'
    old  = '  for slot in exitable_slots(current_pos) {
    open_slots_json.push(open_slot_json(current_pos, slot))
  }'
    new  = '  for slot in current_model().slot_ids() {
    open_slots_json.push(open_slot_json(current_pos, slot))
  }'
  },
  # A domain that has already moved must keep being driven from where it is.
  @{
    name = 'step drives the anchor instead of the current position'
    file = 'backend/loop.mbt'
    old  = '  let chosen = drive_slot(domain_state.position)'
    new  = '  let chosen = drive_slot(domain_state.domain.position())'
  },
  # StepEffect is the classification the cursor depends on. Collapsing Undecided
  # into Advanced is the bug this type was added to fix, and it must stay red.
  @{
    name = 'StepEffect treats an undecided branch as a move'
    file = 'backend/loop.mbt'
    old  = '    Open(_) => Undecided'
    new  = '    Open(_) => Advanced'
  },
  @{
    name = 'StepEffect treats a Block as a move'
    file = 'backend/loop.mbt'
    old  = '    Block(_) => Blocked'
    new  = '    Block(_) => Advanced'
  },
  @{
    name = 'StepEffect treats Same as no move'
    file = 'backend/loop.mbt'
    old  = '    Same(_, _) => Advanced'
    new  = '    Same(_, _) => Undecided'
  },
  # is_undecided is what lets the loop refuse to choose for the subject.
  # A position reachable by two routes is one position, not two futures.
  @{
    name = 'continuations keeps a shorter route alongside the longer one'
    file = 'backend/model.mbt'
    old  = '    } else if continuation.steps < out[index].1 {'
    new  = '    } else if false {'
  },
  @{
    name = 'is_undecided never reports an undecided branch'
    file = 'backend/model.mbt'
    old  = '      Open(_) => return true'
    new  = '      Open(_) => return false'
  },
  # slot_from_designation must consult the model's designation column. It used
  # to carry a hand-written copy of that table, and the copy went stale when
  # pyroduct renamed two of the eight -- the parser went on accepting the
  # old words and rejecting the new ones, which is the whole bug. Reading the
  # table out of the model is what makes that class of failure impossible, so
  # the guard is that the lookup still goes through the designation.
  @{
    name = 'slot_from_designation consults the gloss instead of the designation'
    file = 'backend/model.mbt'
    old  = 'slot.designation.to_lower() == needle'
    new  = 'slot.gloss.to_lower() == needle'
  },
  # The per-domain map must be copied on every step. MoonBit's Map is
  # mutable and is not copy-on-write, so sharing it means the state a step
  # came from changes under the step's feet: the position a session records
  # as "where I was" reads as "where I ended up". Invisible while the old
  # state is thrown away, and wrong the moment somebody keeps it.
  @{
    name = 'the domain states are shared instead of copied'
    file = 'backend/loop.mbt'
    old  = 'let domain_states = copy_domain_states(self.domain_states)'
    new  = 'let domain_states = self.domain_states'
  }
)

# --- run ------------------------------------------------------------------
$survivors = @()
$equivalent = @()
foreach ($m in $mutations) {
  $full = Join-Path $PWD $m.file
  $original = [System.IO.File]::ReadAllText($full)
  try {
    if (-not $original.Contains($m.old)) {
      throw "anchor not present in $($m.file) -- mutation never applied"
    }
    [System.IO.File]::WriteAllText($full, $original.Replace($m.old, $m.new), $enc)
    $out = & moon test --target native 2>&1 | Out-String
    $killed = ($LASTEXITCODE -ne 0) -or ($out -match 'failed: [1-9]')
    if ($killed) {
      Write-Output ("KILLED   {0}" -f $m.name)
    } elseif ($m.equivalent) {
      Write-Output ("EQUIV    {0}" -f $m.name)
      $equivalent += $m.name
    } else {
      Write-Output ("SURVIVED {0}" -f $m.name)
      $survivors += $m.name
    }
  } catch {
    Write-Output ("ERROR    {0} :: {1}" -f $m.name, $_.Exception.Message)
    $survivors += $m.name
  } finally {
    [System.IO.File]::WriteAllText($full, $original, $enc)
  }
}

Write-Output ""
Write-Output ("survivors: {0}   (expected-equivalent: {1})" -f $survivors.Count, $equivalent.Count)
