///| The numbers that say how the run is doing.
///
/// A framework that cannot be measured cannot be falsified, and the question
/// this answers is the one a person has after twenty clicks: "is this run
/// better than the five steps I took before it?"
///
/// Four things are measured, and they are measured over a *window* of the
/// last five steps rather than over the whole run. A number that grows with
/// the length of the run answers "how much did I do", not "how good was it"
/// -- the length is the reader's own doing, and a measure that rose because
/// the run was longer would make every run look like an improvement. The
/// same five-step window is taken at the start of the run and at the end, so
/// the two can be compared, and that comparison is the answer.
///
/// The four measures:
///
///   - new ground: how many of the window's steps reached a position the run
///     had not been on before. This is the information gain, and it is the
///     one that falls to zero when a run begins repeating itself.
///   - settling: how many steps at the end of the window reached nothing
///     new. This is the convergence. A run that is finding ground and a run
///     that is going round in circles look the same on a step counter.
///   - slot spread: how many of the eight slots the window used. This is the
///     path diversity: a run that always drives the same slot is walking one
///     line through the table.
///   - position drift: how many of the thirty-four positions the run has
///     stood on, and how many of them each domain has ranged over.
///
/// No score is combined out of them. One number out of four measures would
/// hide which of them fell, and a number nobody can argue with is the thing
/// this module exists to avoid.
///
/// The sentences are written here, on the server, for the same reason the
/// "why" line and the run summary are: the numbers need the recorded steps
/// and the transition table to say anything true, and a browser that had its
/// own copy of that rule would be a second thing to keep in step with the
/// first.

///|
/// How many steps the measures are taken over.
///
/// Five, because that is the window the run summary already uses: one rule
/// for "the last few steps" in the whole product, and a measure over a
/// different window would answer a different question from the summary
/// printed next to it.
pub const METRIC_WINDOW : Int32 = 5

///|
/// How many domains there are.
///
/// The model's: the five of the ring (M, D, E, A, K) in the built-in model,
/// and whatever a model file says in a model of its own. The same list the
/// run summary counts in, and for the same reason -- the ring is how this
/// project explains itself, and a model file brings its own ring with it.
///
/// A measure whose denominator is a number somebody typed in is a measure
/// that is wrong the moment the machine changes shape.
pub fn domain_count() -> Int32 {
  current_model().domains.length()
}

///|
/// The model's domain letters, in ring order.
pub fn domain_letters() -> Array[String] {
  let letters = []
  for domain in current_model().domains {
    letters.push(domain.letter)
  }
  letters
}

///|
/// One measured number, and the reading that goes with it.
pub(all) struct Metric {
  /// The name it is filed under: "new_ground".
  key : String
  /// The name a reader sees: "New ground".
  label : String
  /// The number itself.
  value : Int32
  /// What the number is out of -- the eight slots, the five domains, the
  /// thirty-four positions -- or 0 when the measure has no denominator.
  of : Int32
  /// The reading, in one sentence.
  sentence : String
}

///|
/// The report: the measures, and the comparison of the run's beginning with
/// its end.
pub(all) struct MetricReport {
  /// The window the measures are taken over.
  window : Int32
  /// How many steps the window actually holds. It is fewer than the window
  /// at the start of a run, and that is why the sentences say "the last 3
  /// steps" rather than "the last 5".
  window_steps : Int32
  /// The measures themselves.
  metrics : Array[Metric]
  /// The comparison between the first window and the last one. Empty when
  /// the run is too short for the two to be separate windows.
  comparison : String
}

///|
/// Measure a path.
///
/// The path is the session's *current* path, not every step the session has
/// recorded: the branches that are not on the path were not taken, and
/// counting them would say the run went somewhere it did not go.
///
/// A run with no steps in it has nothing to measure, and the report says so
/// by having no measures in it -- the same way the run summary is empty for
/// an empty run, so a client can leave the block out rather than print
/// zeroes at someone.
pub fn measure(path : Array[SessionStep], lang : Lang) -> MetricReport {
  let n = path.length()
  let window = METRIC_WINDOW
  if n == 0 {
    return { window, window_steps: 0, metrics: [], comparison: "", }
  }
  let start = if n > window { n - window } else { 0 }
  let recent = slice_from(path, start)
  let fresh = new_ground_flags(path)
  let metrics : Array[Metric] = [
    new_ground_metric(recent, fresh, start, lang),
    settling_metric(recent, fresh, start, lang),
    slot_spread_metric(recent, lang),
    domain_spread_metric(recent, lang),
    position_drift_metric(path, lang),
  ]
  {
    window,
    window_steps: recent.length(),
    metrics,
    comparison: comparison_sentence(path, fresh, lang),
  }
}

///|
/// The steps from `start` to the end of the path.
fn slice_from(path : Array[SessionStep], start : Int32) -> Array[SessionStep] {
  let out : Array[SessionStep] = []
  let mut i = start
  while i < path.length() {
    out.push(path[i])
    i += 1
  }
  out
}

///|
/// For each step: did it reach a position the run had not stood on before?
///
/// The position a step came from counts as occupied, and so does every
/// position an earlier step reached. So a step that did not move is never
/// new ground -- which is right: a step that went nowhere added nothing to
/// the map.
fn new_ground_flags(path : Array[SessionStep]) -> Array[Bool] {
  let flags : Array[Bool] = []
  let occupied : Array[String] = []
  for step in path {
    push_unique(occupied, step.position_before)
    let fresh = !contains_string(occupied, step.position_after)
    push_unique(occupied, step.position_after)
    flags.push(fresh)
  }
  flags
}

///|
/// Whether a list holds a string.
fn contains_string(list : Array[String], needle : String) -> Bool {
  for item in list {
    if item == needle {
      return true
    }
  }
  false
}

///|
/// Add a string to a list, unless it is already there.
fn push_unique(list : Array[String], value : String) -> Unit {
  if !contains_string(list, value) {
    list.push(value)
  }
}

///|
/// How many of the steps between `from` and `to` reached new ground.
fn count_fresh(fresh : Array[Bool], from : Int32, to : Int32) -> Int32 {
  let mut count = 0
  let mut i = from
  while i < to && i < fresh.length() {
    if fresh[i] {
      count += 1
    }
    i += 1
  }
  count
}

///|
/// "The last 5 steps", or "The last step" when there is only one.
///
/// A sentence that says "the last 1 steps" is a machine talking to itself,
/// and the window is one step long at the start of every run.
fn last_steps_clause(count : Int32, lang : Lang) -> String {
  match lang {
    English =>
      if count == 1 {
        "The last step"
      } else {
        "The last " + count.to_string() + " steps"
      }
    Chinese =>
      if count == 1 {
        "最后一步"
      } else {
        "最后" + count_word_zh(count) + "步"
      }
  }
}

///|
/// New ground: how many of the window's steps reached a position the run had
/// not been on before.
///
/// This is the information gain. It is the measure that goes to zero when a
/// run starts repeating itself, and it is the one the comparison is made on.
fn new_ground_metric(
  recent : Array[SessionStep],
  fresh : Array[Bool],
  start : Int32,
  lang : Lang,
) -> Metric {
  let count = count_fresh(fresh, start, fresh.length())
  let w = recent.length()
  let sentence = match lang {
    English =>
      if w == 1 {
        if count == 0 {
          "The last step reached no position the run had not been on before: it added nothing to the map."
        } else {
          "The last step reached a position the run had not been on before."
        }
      } else if count == 0 {
        "The last " +
        w.to_string() +
        " steps reached no position the run had not been on before: they added nothing to the map."
      } else {
        count.to_string() +
        " of the last " +
        w.to_string() +
        " steps reached a position the run had not been on before."
      }
    Chinese =>
      if w == 1 {
        if count == 0 {
          "最后一步没有到达本次运行此前未曾站过的位置：它没有为地图增添任何东西。"
        } else {
          "最后一步到达了本次运行此前未曾站过的位置。"
        }
      } else if count == 0 {
        "最后" +
        count_word_zh(w) +
        "步没有到达本次运行此前未曾站过的位置：它们没有为地图增添任何东西。"
      } else {
        "最后" +
        count_word_zh(w) +
        "步中有" +
        count_word_zh(count) +
        "步到达了本次运行此前未曾站过的位置。"
      }
  }
  {
    key: "new_ground",
    label: lang.pick("New ground", "新增地盘"),
    value: count,
    of: w,
    sentence,
  }
}

///|
/// Settling: how many steps at the end of the window reached nothing new.
///
/// This is the convergence. It counts the *trailing* steps rather than all
/// of them, because "the last 3 steps reached nothing new" says something
/// different from "3 of the last 5 steps reached nothing new": the first is
/// about the run's shape now, the second is about its average.
///
/// A run that reached nothing new because it *moved* into a position it
/// already knew is settling, and that is the goal. A run that reached
/// nothing new because it did not move at all is stuck, and the two are not
/// the same thing: one is a run that has arrived somewhere, the other is a
/// run that has stopped. The recorded outcome tells them apart -- "Moved" is
/// the only outcome that puts the subject somewhere else -- so the measure
/// says which of the two it is looking at.
fn settling_metric(
  recent : Array[SessionStep],
  fresh : Array[Bool],
  start : Int32,
  lang : Lang,
) -> Metric {
  let mut settling = 0
  let mut stuck = 0
  let mut i = fresh.length() - 1
  while i >= start {
    if fresh[i] {
      break
    }
    settling += 1
    // A step that did not move cannot have found new ground: it left the
    // subject where it was, and where it was is a position the run had
    // already stood on.
    if !moved_outcome(recent[i - start].outcome_kind) {
      stuck += 1
    }
    i -= 1
  }
  let sentence = match lang {
    English =>
      if settling == 0 {
        "The last step reached a position the run had not been on before, so the run is still finding new ground."
      } else if stuck == settling {
        if settling == 1 {
          "The last step did not move the subject at all: the run is stuck, not settling."
        } else {
          "The last " +
          settling.to_string() +
          " steps did not move the subject at all: the run is stuck, not settling."
        }
      } else if settling == 1 {
        "The last step reached nothing new: the run has just stopped finding new ground."
      } else {
        "The last " +
        settling.to_string() +
        " steps reached nothing new: the run is settling rather than exploring."
      }
    Chinese =>
      if settling == 0 {
        "最后一步到达了本次运行此前未曾站过的位置，因此运行仍在开辟新地盘。"
      } else if stuck == settling {
        if settling == 1 {
          "最后一步根本没有移动主体：这是卡住了，而不是在沉降。"
        } else {
          "最后" +
          count_word_zh(settling) +
          "步根本没有移动主体：这是卡住了，而不是在沉降。"
        }
      } else if settling == 1 {
        "最后一步没有开辟任何新东西：运行刚刚停止了开辟新地盘。"
      } else {
        "最后" +
        count_word_zh(settling) +
        "步没有开辟任何新东西：运行正在沉降，而不是在探索。"
      }
  }
  {
    key: "settling",
    label: lang.pick("Settling", "沉降"),
    value: settling,
    of: 0,
    sentence,
  }
}

///|
/// Whether a step moved the subject anywhere.
///
/// "moved" is the only outcome that puts the subject on a different position.
/// Held keeps it where it is on purpose, Open is the table declining to
/// choose between successors, and Block is a gap in the table. None of the
/// three is movement, and a run made of them has not gone anywhere.
///
/// The kind is compared against, not the word. The word belongs to the model
/// and a model file may rename it, and a measure that carried its own copy of
/// the vocabulary would call a renamed move "something else" and report a run
/// that moved as a run that did not -- which is the difference between a
/// measure and a guess.
fn moved_outcome(outcome_kind : String) -> Bool {
  outcome_kind == "moved"
}

///|
/// Slot spread: how many of the eight slots the window used.
///
/// This is the path diversity. A run that always drives the same slot is
/// walking one line through the table, and the step counter cannot see the
/// difference.
fn slot_spread_metric(recent : Array[SessionStep], lang : Lang) -> Metric {
  let model = current_model()
  let names : Array[String] = []
  for step in recent {
    // The English is the designation the step recorded, because that is what
    // the reader saw when the step was taken. The Chinese is the model's own
    // name for the slot, read out of the model rather than carried on the
    // step.
    names.push(
      match lang {
        English => step.slot_designation
        Chinese => model.slot_designation_in(step.slot, Chinese)
      },
    )
  }
  let counts = tally(names)
  let distinct = counts.length()
  let total = current_model().slots.length()
  let (top, top_count) = most_used(counts)
  let w = recent.length()
  let sentence = match lang {
    English =>
      if top_count > 1 {
        last_steps_clause(w, English) +
        " used " +
        distinct.to_string() +
        " of the " +
        total.to_string() +
        " slots, and " +
        top +
        " was used " +
        top_count.to_string() +
        " times."
      } else if w == 1 {
        "The last step used " +
        distinct.to_string() +
        " of the " +
        total.to_string() +
        " slots."
      } else {
        last_steps_clause(w, English) +
        " used " +
        distinct.to_string() +
        " of the " +
        total.to_string() +
        " slots, each of them once."
      }
    Chinese =>
      if top_count > 1 {
        last_steps_clause(w, Chinese) +
        "用了" +
        total.to_string() +
        "个槽位中的" +
        count_word_zh(distinct) +
        "个，其中「" +
        top +
        "」用了" +
        count_phrase_zh(top_count) +
        "。"
      } else if w == 1 {
        "最后一步用了" +
        total.to_string() +
        "个槽位中的" +
        count_word_zh(distinct) +
        "个。"
      } else {
        last_steps_clause(w, Chinese) +
        "用了" +
        total.to_string() +
        "个槽位中的" +
        count_word_zh(distinct) +
        "个，每个各用一次。"
      }
  }
  {
    key: "slot_spread",
    label: lang.pick("Slots used", "用过的槽位"),
    value: distinct,
    of: total,
    sentence,
  }
}

///|
/// Domain spread: how many of the five domains the window visited.
fn domain_spread_metric(recent : Array[SessionStep], lang : Lang) -> Metric {
  let letters : Array[String] = []
  for step in recent {
    letters.push(step.domain)
  }
  let distinct = tally(letters).length()
  let sentence = match lang {
    English =>
      last_steps_clause(recent.length(), English) +
      " visited " +
      distinct.to_string() +
      " of the " +
      domain_count().to_string() +
      " domains."
    Chinese =>
      last_steps_clause(recent.length(), Chinese) +
      "走过" +
      domain_count().to_string() +
      "个域中的" +
      count_word_zh(distinct) +
      "个。"
  }
  {
    key: "domain_spread",
    label: lang.pick("Domains visited", "走过的域"),
    value: distinct,
    of: domain_count(),
    sentence,
  }
}

///|
/// Position drift: how many of the positions the run has stood on, and how
/// many of them each domain has ranged over.
///
/// The denominator is read out of the model rather than written down here:
/// the size of the state space is the machine's business, and a number
/// copied into MAKED would be wrong the day the table grew.
fn position_drift_metric(path : Array[SessionStep], lang : Lang) -> Metric {
  let model = current_model()
  let total = model.positions.length()
  let all : Array[String] = []
  let per_domain : Array[(String, Int32)] = []
  for letter in domain_letters() {
    let positions : Array[String] = []
    for step in path {
      if step.domain == letter {
        push_unique(positions, step.position_before)
        push_unique(positions, step.position_after)
      }
    }
    if positions.length() > 0 {
      per_domain.push((letter, positions.length()))
      for position in positions {
        push_unique(all, position)
      }
    }
  }
  let covered = all.length()
  let sentence = match lang {
    English =>
      "So far the run has stood on " +
      covered.to_string() +
      " of the " +
      total.to_string() +
      " positions. " +
      drift_clause(model, per_domain, English) +
      "."
    Chinese =>
      "到目前为止，本次运行在" +
      total.to_string() +
      "个位置中站过" +
      count_word_zh(covered) +
      "个。" +
      drift_clause(model, per_domain, Chinese) +
      "。"
  }
  {
    key: "position_drift",
    label: lang.pick("Positions covered", "覆盖的位置"),
    value: covered,
    of: total,
    sentence,
  }
}

///|
/// The per-domain part of the drift sentence, in ring order.
///
/// How far each domain ranged, which is not a share of the total: two domains
/// can stand on the same position, and then the parts add up to more than
/// the whole. So the sentence says "ranged over", and leaves the total to
/// the sentence before it.
///
/// The first part is capitalised, because it follows a full stop: the total
/// and the parts are two sentences, and a sentence that starts in the
/// middle of the alphabet reads as a typo.
fn drift_clause(
  model : Model,
  per_domain : Array[(String, Int32)],
  lang : Lang,
) -> String {
  let parts : Array[String] = []
  for (letter, count) in per_domain {
    parts.push(
      match lang {
        English =>
          role_of(model, letter) + " has ranged over " + count.to_string()
        Chinese =>
          role_of_in(model, letter, Chinese) +
          "走过了" +
          count_word_zh(count) +
          "个位置"
      },
    )
  }
  if parts.length() == 0 {
    return ""
  }
  match lang {
    English => {
      parts[0] = capitalize(parts[0])
      join_parts(parts)
    }
    Chinese => join_list_zh(parts)
  }
}

///|
/// The comparison that answers "is twenty steps better than five".
///
/// The last window of steps against the first window of steps, on the measure
/// that says whether a run is still finding ground. A run that is finding
/// less new ground than it did at the start is not improving, however many
/// steps it has taken -- and saying so is the whole point of measuring.
///
/// The two windows have to be separate, so a run shorter than two windows
/// cannot be compared with itself yet. It says so rather than comparing
/// overlapping windows, which would make the last five steps part of the
/// first five and the comparison meaningless.
fn comparison_sentence(
  path : Array[SessionStep],
  fresh : Array[Bool],
  lang : Lang,
) -> String {
  let n = path.length()
  let window = METRIC_WINDOW
  if n < window * 2 {
    return match lang {
      English => {
        let steps = if n == 1 {
          "The run has 1 step"
        } else {
          "The run has " + n.to_string() + " steps"
        }
        steps +
        ", so its beginning and its end cannot be compared yet: the comparison needs " +
        (window * 2).to_string() +
        "."
      }
      Chinese => {
        let steps = if n == 1 {
          "本次运行有一步"
        } else {
          "本次运行有" + count_word_zh(n) + "步"
        }
        steps +
        "，因此它的开头与结尾暂时还无法比较：比较需要" +
        (window * 2).to_string() +
        "步。"
      }
    }
  }
  let first = count_fresh(fresh, 0, window)
  let last = count_fresh(fresh, n - window, n)
  match lang {
    English => {
      let head = "The last " +
        window.to_string() +
        " steps reached " +
        last.to_string() +
        " new positions; the first " +
        window.to_string() +
        " reached " +
        first.to_string() +
        "."
      if last > first {
        head + " The run is finding more new ground than it did at the start."
      } else if last < first {
        head + " The run is finding less new ground than it did at the start."
      } else {
        head + " The run is holding its rate."
      }
    }
    Chinese => {
      let head = "最后" +
        count_word_zh(window) +
        "步到达了" +
        count_word_zh(last) +
        "个新位置；最初的" +
        count_word_zh(window) +
        "步到达了" +
        count_word_zh(first) +
        "个。"
      if last > first {
        head + "本次运行开辟的新地盘比开始时更多。"
      } else if last < first {
        head + "本次运行开辟的新地盘比开始时更少。"
      } else {
        head + "本次运行保持住了它的速率。"
      }
    }
  }
}

///|
/// How many times each name was used, in the order the names first appear.
fn tally(items : Array[String]) -> Array[(String, Int32)] {
  let counts : Array[(String, Int32)] = []
  for item in items {
    let at = index_of(counts, item)
    if at < 0 {
      counts.push((item, 1))
    } else {
      let (name, n) = counts[at]
      counts[at] = (name, n + 1)
    }
  }
  counts
}

///|
/// The index of the first entry with this name, or -1 when there is none.
fn index_of(entries : Array[(String, Int32)], name : String) -> Int32 {
  let mut i = 0
  while i < entries.length() {
    let (entry_name, _) = entries[i]
    if entry_name == name {
      return i
    }
    i += 1
  }
  -1
}

///|
/// The most used name and how many times it was used.
///
/// The first one wins a tie, and the names are in the order they first
/// appear, so the answer does not change from one run to the next over the
/// same path.
fn most_used(counts : Array[(String, Int32)]) -> (String, Int32) {
  let mut top = ""
  let mut top_count = 0
  for (name, n) in counts {
    if n > top_count {
      top = name
      top_count = n
    }
  }
  (top, top_count)
}

///|
/// A list of phrases, with an "and" before the last one.
fn join_parts(parts : Array[String]) -> String {
  if parts.length() == 0 {
    return ""
  }
  if parts.length() == 1 {
    return parts[0]
  }
  let head : Array[String] = []
  let last = parts.length() - 1
  let mut i = 0
  while i < last {
    head.push(parts[i])
    i += 1
  }
  head.join(", ") + " and " + parts[last]
}

///|
/// One measure, as the API reports it.
pub fn Metric::to_json(self : Metric) -> Json {
  {
    "key": self.key,
    "label": self.label,
    "value": self.value,
    "of": self.of,
    "sentence": self.sentence,
  }
}

///|
/// The report, as the API reports it.
pub fn MetricReport::to_json(self : MetricReport) -> Json {
  let items : Array[Json] = []
  for metric in self.metrics {
    items.push(metric.to_json())
  }
  {
    "window": self.window,
    "window_steps": self.window_steps,
    "metrics": [..items],
    "comparison": self.comparison,
  }
}
