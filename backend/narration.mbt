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
  }
}

///|
/// One step, told as a sentence.
///
/// Two sentences, because there are two things to say. The first is what
/// happened to the domain. The second is why that slot was the one used, and
/// where the cursor went next -- "the table chose this" and "you chose this"
/// are different claims, and the outcome alone does not tell them apart.
pub fn step_sentence(facts : StepFacts) -> String {
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
      provenance(facts) +
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
      provenance(facts) +
      ", and " +
      cursor +
      "."
    "open" =>
      "The table offered " +
      facts.role +
      " several ways out of " +
      facts.position_before +
      " and declined to choose between them. " +
      provenance(facts) +
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
      provenance(facts) +
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
/// Where the slot came from, as the second half of a step's sentence.
fn provenance(facts : StepFacts) -> String {
  match facts.source {
    "explicit" => facts.slot + " was the slot you chose"
    "research" => facts.slot + " was the slot the research run chose"
    _ => facts.slot + " was the slot the table drives with here"
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
  let run = run_clause(model, steps)
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
/// The first clause of a summary: where the run went.
fn run_clause(model : Model, steps : Array[StepFacts]) -> String {
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
