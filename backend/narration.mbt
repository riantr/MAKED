///| The sentences that make the loop legible.
///
/// The machine's own words come from the model: the position labels, the slot
/// designations, the domain titles. What was missing is the sentence that
/// ties them together -- why a step was taken, what it changed, and what a
/// run of steps adds up to.
///
/// A reader who sees "M - Action - Moved" has learned nothing. A reader who
/// sees "The model formulator moved from Standing to Freedom through
/// Action. Action was the slot the table drives with here, and the cursor
/// advanced to the data turbine" can follow what the machine is doing
/// without knowing what "Standing" means.
///
/// These sentences are written on the server, for the same reason the "why"
/// line is: a second copy in the browser would be a second thing to keep in
/// step with the first, and the one in the browser would be the one that
/// drifts.

///|
/// What one step did, in the words a sentence needs.
///
/// Filled from a recorded step, so the sentence describes the step that was
/// taken rather than the table as it stands now.
pub(all) struct StepFacts {
  /// The domain's letter: "M".
  letter : String
  /// The domain's title: "Model".
  domain : String
  /// The domain's role, as a phrase with its article: "the model formulator".
  role : String
  /// The slot's designation: "Action".
  slot : String
  /// The outcome's kind: "moved", "held", "same", "open" or "block".
  ///
  /// This is the kind and not the word, and that is the whole point of the
  /// change. The word -- "Moved", "Held", "Converge", "Undecided", "No-way" --
  /// belongs to the model, and a model file is free to rename it. A sentence
  /// built by matching on the word would then describe the wrong kind of
  /// step: a model that calls an open branch "Unsure" would get the sentence
  /// for an undecided step only by accident, and a model that called a move
  /// something else would get no sentence at all.
  outcome_kind : String
  /// Where the domain stood before the step.
  position_before : String
  /// Where it ended up. The same as `position_before` when nothing moved.
  position_after : String
  /// The domain the cursor points at now, as a phrase: "the data turbine".
  cursor : String
  /// How the step was taken: "drive" (the table's own choice), "explicit" (a
  /// person picked the slot) or "research".
  source : String
  /// How many slots had an outgoing edge at the position the step was taken
  /// from. Zero means the position had no road out at all, which is a
  /// different sentence from a slot that was tried and had none.
  available : Int32
  /// The role in Chinese: "模型构建者".
  ///
  /// The Chinese role carries no article, because Chinese has none, and the
  /// sentence templates are written accordingly rather than being a
  /// translation with the article left in.
  role_zh : String
  /// The slot in Chinese: "行动".
  slot_zh : String
  /// Where the domain stood, in Chinese: "立位".
  position_before_zh : String
  /// Where it ended up, in Chinese.
  position_after_zh : String
  /// The cursor's domain, in Chinese.
  cursor_zh : String
}

///|
/// The role phrase for a domain letter, or the letter itself when the model
/// has no such domain.
///
/// The phrase is the model's. A model file gives each of its own domains a
/// role -- "the idea", "the shipping" -- and a domain the model does not have
/// is a domain MAKED cannot describe, so the letter is the honest answer.
pub fn role_of(model : Model, letter : String) -> String {
  match model.domain_by_letter(letter) {
    Some(domain) => domain.role()
    None => letter
  }
}

///|
/// The role phrase for a domain letter, in the language asked for.
///
/// A domain the model does not have has no role in either language, so the
/// letter is the honest answer there too -- and it is the same letter in
/// both, because a letter is a letter.
pub fn role_of_in(model : Model, letter : String, lang : Lang) -> String {
  match model.domain_by_letter(letter) {
    Some(domain) => domain.role_in(lang)
    None => letter
  }
}

///|
/// The name of a slot, in the language asked for.
///
/// The stored designation is the fallback: a step recorded against a slot the
/// model no longer has still has a name, and showing that name is better
/// than showing nothing.
fn slot_name_in(
  model : Model,
  id : String,
  stored : String,
  lang : Lang,
) -> String {
  let name = model.slot_designation_in(id, lang)
  if name == "" {
    stored
  } else {
    name
  }
}

///|
/// The name of a position, in the language asked for.
///
/// A recorded step stores the *name* of a position rather than its id, so
/// the name is what the model is asked about. A name the model does not have
/// is shown as it was recorded, which is the only honest thing left to show.
fn position_name_in(model : Model, stored : String, lang : Lang) -> String {
  match model.position_by_label(stored) {
    Some(position) => lang.pick(position.label, position.label_zh)
    None => stored
  }
}

///|
/// The facts of a recorded step, for the sentences to be written from.
///
/// The model is asked, because the role and the cursor's role are the
/// model's words: a step recorded on somebody else's machine is described
/// with that machine's domains, not with MAKED's five.
pub fn facts_of(model : Model, step : SessionStep) -> StepFacts {
  {
    letter: step.domain,
    domain: step.domain_title,
    role: role_of(model, step.domain),
    slot: step.slot_designation,
    outcome_kind: step.outcome_kind,
    position_before: step.position_before,
    position_after: step.position_after,
    cursor: role_of(model, step.cursor_after),
    source: step.source,
    available: split_slots(step.available).length(),
    role_zh: role_of_in(model, step.domain, Chinese),
    slot_zh: slot_name_in(model, step.slot, step.slot_designation, Chinese),
    position_before_zh: position_name_in(model, step.position_before, Chinese),
    position_after_zh: position_name_in(model, step.position_after, Chinese),
    cursor_zh: role_of_in(model, step.cursor_after, Chinese),
  }
}

///|
/// One step, told as a sentence.
///
/// Two sentences, because there are two things to say. The first is what
/// happened to the domain. The second is why that slot was the one used, and
/// where the cursor went next -- "the table chose this" and "you chose this"
/// are different claims, and the outcome alone does not tell them apart.
///
/// The language is the reader's, and the two are written rather than
/// translated: Chinese has no article, so the subject is the role on its own,
/// and it has no capital letters, so there is nothing to capitalise. A
/// sentence that were a translation of the English would carry the English
/// shape into a language that does not have it.
pub fn step_sentence(facts : StepFacts, lang : Lang) -> String {
  match lang {
    English => step_sentence_en(facts)
    Chinese => step_sentence_zh(facts)
  }
}

///|
/// One step, told as a sentence, in English.
fn step_sentence_en(facts : StepFacts) -> String {
  let subject = capitalize(facts.role)
  let cursor = if facts.cursor == facts.role {
    "the cursor stayed on " + facts.role
  } else {
    "the cursor advanced to " + facts.cursor
  }
  match facts.outcome_kind {
    "moved" =>
      subject +
      " moved from " +
      facts.position_before +
      " to " +
      facts.position_after +
      " through " +
      facts.slot +
      ". " +
      provenance_en(facts) +
      ", and " +
      cursor +
      "."
    "held" =>
      subject +
      " held at " +
      facts.position_before +
      " through " +
      facts.slot +
      ": the table had a road there, but not one that moved it. " +
      provenance_en(facts) +
      ", and " +
      cursor +
      "."
    "open" =>
      "The table offered " +
      facts.role +
      " several ways out of " +
      facts.position_before +
      " and declined to choose between them. " +
      provenance_en(facts) +
      ", and " +
      cursor +
      "."
    "same" =>
      "Several triggers converged on " +
      facts.position_before +
      " for " +
      facts.role +
      " through " +
      facts.slot +
      ", which is the table confirming the position rather than changing it. " +
      provenance_en(facts) +
      ", and " +
      cursor +
      "."
    "block" =>
      if facts.available == 0 {
        "Nothing could move " +
        facts.role +
        " at " +
        facts.position_before +
        ": no slot has a road out of there. " +
        capitalize(cursor) +
        "."
      } else {
        "Nothing could move " +
        facts.role +
        " at " +
        facts.position_before +
        " through " +
        facts.slot +
        ": that slot has no road out of there. " +
        capitalize(cursor) +
        "."
      }
    _ =>
      subject +
      " took " +
      facts.slot +
      " and ended at " +
      facts.position_after +
      ". " +
      capitalize(cursor) +
      "."
  }
}

///|
/// One step, told as a sentence, in Chinese.
///
/// Written in Chinese rather than translated, which shows in three places.
/// The subject has no article: "模型构建者" and not "模型构建者这个". There is
/// nothing to capitalise. And the two halves are joined by a comma rather
/// than by "and", because a Chinese sentence does not spell out the
/// conjunction between two clauses that are already in order.
fn step_sentence_zh(facts : StepFacts) -> String {
  let subject = facts.role_zh
  let cursor = if facts.cursor_zh == facts.role_zh {
    "光标仍在" + facts.role_zh + "上"
  } else {
    "光标移向" + facts.cursor_zh
  }
  match facts.outcome_kind {
    "moved" =>
      subject +
      "经由" +
      facts.slot_zh +
      "从" +
      facts.position_before_zh +
      "迁移到" +
      facts.position_after_zh +
      "。" +
      provenance_zh(facts) +
      "，" +
      cursor +
      "。"
    "held" =>
      subject +
      "经由" +
      facts.slot_zh +
      "守在" +
      facts.position_before_zh +
      "：表格在这里有路，但没有一条能推动它。" +
      provenance_zh(facts) +
      "，" +
      cursor +
      "。"
    "open" =>
      "表格给出了" +
      facts.role_zh +
      "从" +
      facts.position_before_zh +
      "出去的几条路，却不肯在其中做选择。" +
      provenance_zh(facts) +
      "，" +
      cursor +
      "。"
    "same" =>
      "若干触发经由" +
      facts.slot_zh +
      "在" +
      facts.position_before_zh +
      "上汇合，这是表格为" +
      facts.role_zh +
      "确认位置，而不是改变位置。" +
      provenance_zh(facts) +
      "，" +
      cursor +
      "。"
    "block" =>
      if facts.available == 0 {
        "没有任何东西能在" +
        facts.position_before_zh +
        "推动" +
        facts.role_zh +
        "：那里没有哪个槽有路出去。" +
        cursor +
        "。"
      } else {
        "没有任何东西能经由" +
        facts.slot_zh +
        "在" +
        facts.position_before_zh +
        "推动" +
        facts.role_zh +
        "：那个槽在那里没有路出去。" +
        cursor +
        "。"
      }
    _ =>
      subject +
      "取用了" +
      facts.slot_zh +
      "，最终停在" +
      facts.position_after_zh +
      "。" +
      cursor +
      "。"
  }
}

///|
/// Where the slot came from, as the second half of a step's sentence.
fn provenance_en(facts : StepFacts) -> String {
  match facts.source {
    "explicit" => facts.slot + " was the slot you chose"
    "research" => facts.slot + " was the slot the research run chose"
    _ => facts.slot + " was the slot the table drives with here"
  }
}

///|
/// Where the slot came from, in Chinese.
fn provenance_zh(facts : StepFacts) -> String {
  match facts.source {
    "explicit" => facts.slot_zh + "是你选择的槽"
    "research" => facts.slot_zh + "是研究运行选择的槽"
    _ => facts.slot_zh + "是此处表格用来驱动的槽"
  }
}

///|
/// What a run of steps adds up to.
///
/// The question a person actually has after five clicks is not "what did
/// step four do" -- that is in the timeline -- but "what have these five
/// steps done between them". This answers that: which domains the run
/// visited, how many of its steps actually moved a position, and where the
/// group stands.
///
/// Empty when there is nothing to summarise, so a caller can leave the line
/// out rather than print an empty one.
pub fn phase_summary(
  model : Model,
  steps : Array[StepFacts],
  group_state : String,
  lang : Lang,
) -> String {
  match lang {
    English => phase_summary_en(model, steps, group_state)
    Chinese => phase_summary_zh(model, steps, group_state)
  }
}

///|
/// What a run of steps adds up to, in English.
fn phase_summary_en(
  model : Model,
  steps : Array[StepFacts],
  group_state : String,
) -> String {
  let n = steps.length()
  if n == 0 {
    return ""
  }
  let mut moved = 0
  for step in steps {
    if step.outcome_kind == "moved" {
      moved += 1
    }
  }
  let run = run_clause_en(model, steps)
  let movement = if n == 1 {
    if moved == 1 {
      "It moved a position."
    } else {
      "It did not move a position."
    }
  } else if moved == 0 {
    "None of them moved a position."
  } else if moved == 1 {
    "One of them moved a position."
  } else {
    count_word(moved) + " of them moved a position."
  }
  let group = if group_state == "" {
    ""
  } else {
    " The group is " + group_state + "."
  }
  run + " " + movement + group
}

///|
/// What a run of steps adds up to, in Chinese.
///
/// The group state is translated on the way in: it is recorded in English,
/// because that is the model's own reading of it, and the group vocabulary
/// is fixed, so the Chinese name of a recorded group state is a lookup rather
/// than a guess.
fn phase_summary_zh(
  model : Model,
  steps : Array[StepFacts],
  group_state : String,
) -> String {
  let n = steps.length()
  if n == 0 {
    return ""
  }
  let mut moved = 0
  for step in steps {
    if step.outcome_kind == "moved" {
      moved += 1
    }
  }
  let run = run_clause_zh(model, steps)
  let movement = if n == 1 {
    if moved == 1 {
      "它移动了一个位置。"
    } else {
      "它没有移动位置。"
    }
  } else if moved == 0 {
    "其中没有一步移动位置。"
  } else if moved == 1 {
    "其中一步移动了位置。"
  } else {
    "其中" + count_word_zh(moved) + "步移动了位置。"
  }
  let group = if group_state == "" {
    ""
  } else {
    "群体处于" + group_state_in(group_state, Chinese) + "状态。"
  }
  run + movement + group
}

///|
/// The first clause of a summary: where the run went.
fn run_clause_en(model : Model, steps : Array[StepFacts]) -> String {
  let n = steps.length()
  let counts = count_domains(model, steps)
  if counts.length() == 1 {
    let role = role_of(model, counts[0].0)
    if n == 1 {
      "The last step was in " + role + "."
    } else {
      "The last " + n.to_string() + " steps were all in " + role + "."
    }
  } else {
    let parts : Array[String] = []
    for (letter, count) in counts {
      parts.push(role_of(model, letter) + " " + count_phrase(count))
    }
    "The last " + n.to_string() + " steps visited " + join_list(parts) + "."
  }
}

///|
/// The first clause of a summary, in Chinese.
///
/// The count is written in words rather than in digits, because the digits
/// would be the only Latin numerals in the sentence and a Chinese sentence
/// with one of them in the middle of it reads as a translation.
fn run_clause_zh(model : Model, steps : Array[StepFacts]) -> String {
  let n = steps.length()
  let counts = count_domains(model, steps)
  if counts.length() == 1 {
    let role = role_of_in(model, counts[0].0, Chinese)
    if n == 1 {
      "最后一步在" + role + "中。"
    } else {
      "最后" + count_word_zh(n) + "步都在" + role + "中。"
    }
  } else {
    let parts : Array[String] = []
    for (letter, count) in counts {
      parts.push(role_of_in(model, letter, Chinese) + count_phrase_zh(count))
    }
    "最后" + count_word_zh(n) + "步走访了" + join_list_zh(parts) + "。"
  }
}

///|
/// How many times each domain was stepped, in ring order.
///
/// Ring order rather than order of first appearance: the ring is how this
/// project explains itself, and a count that followed the click order would
/// read as an accident.
///
/// The ring is the model's, so the order is the model's too. A model with two
/// domains has a two-domain ring, and the five of MAKED's own are not
/// consulted -- a run in a domain the model does not have is not counted at
/// all, because there is no lens there to count.
fn count_domains(
  model : Model,
  steps : Array[StepFacts],
) -> Array[(String, Int32)] {
  let out : Array[(String, Int32)] = []
  for domain in model.domains {
    let mut count = 0
    for step in steps {
      if step.letter == domain.letter {
        count += 1
      }
    }
    if count > 0 {
      out.push((domain.letter, count))
    }
  }
  out
}

///|
/// A count, in words when it is small enough to read that way.
///
/// "One", "Two", "Three": a sentence that says "4 of them moved" is a
/// spreadsheet talking, and one that says "Four of them moved" is a person
/// talking. Past ten the digits are the shorter answer, and the sentence is
/// long enough already.
fn count_word(count : Int32) -> String {
  match count {
    1 => "One"
    2 => "Two"
    3 => "Three"
    4 => "Four"
    5 => "Five"
    6 => "Six"
    7 => "Seven"
    8 => "Eight"
    9 => "Nine"
    10 => "Ten"
    _ => count.to_string()
  }
}

///|
/// A count, in Chinese words when it is small enough to read that way.
///
/// Chinese counts the same way English does: one character per digit up to
/// ten, and digits past that, because the sentence is long enough already.
fn count_word_zh(count : Int32) -> String {
  match count {
    1 => "一"
    2 => "两"
    3 => "三"
    4 => "四"
    5 => "五"
    6 => "六"
    7 => "七"
    8 => "八"
    9 => "九"
    10 => "十"
    _ => count.to_string()
  }
}

///|
/// A count, in words: "once", "twice", "three times".
fn count_phrase(count : Int32) -> String {
  if count == 1 {
    "once"
  } else if count == 2 {
    "twice"
  } else if count <= 10 {
    count_word(count).to_lower() + " times"
  } else {
    count.to_string() + " times"
  }
}

///|
/// A count, in Chinese: "一次", "两次", "三次".
///
/// Two is 两 and not 二 here, because the counting word is the one that
/// takes the classifier, and 两 is the counting form of two.
fn count_phrase_zh(count : Int32) -> String {
  if count == 1 {
    "一次"
  } else if count == 2 {
    "两次"
  } else if count <= 10 {
    count_word_zh(count) + "次"
  } else {
    count.to_string() + "次"
  }
}

///|
/// A list of phrases, with an "and" before the last one.
fn join_list(parts : Array[String]) -> String {
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
/// A list of phrases, in Chinese.
///
/// The list mark is the enumeration comma rather than the Latin comma, and
/// the last item is joined with 和 rather than with "and": a Chinese list
/// reads "甲、乙和丙", and putting a Latin comma in it is a small thing
/// that makes the whole sentence look translated.
fn join_list_zh(parts : Array[String]) -> String {
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
  head.join("、") + "和" + parts[last]
}

///|
/// The first letter of a phrase, upper-cased.
///
/// Only the first letter changes: the rest of the phrase is a name, and a
/// name in title case would be a different name.
///
/// A String's index gives the character's *code*, not the character, so the
/// first letter is taken apart by hand: an ASCII lower-case letter sits 32
/// below its upper-case twin, and anything else is left exactly as it is.
pub fn capitalize(text : String) -> String {
  if text.length() == 0 {
    return text
  }
  let code = text[0]
  if code < 97 || code > 122 {
    return text
  }
  let head = match (code - 32).to_char() {
    Some(c) => c.to_string()
    None => return text
  }
  head + text[1:].to_owned()
}
