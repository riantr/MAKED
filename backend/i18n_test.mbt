///| The other language.
///
/// A model is the same machine in either language, and the tests here are
/// about that: the same ids, the same rules, the same sentences' facts -- and
/// two vocabularies rather than one. What they are *not* about is Chinese
/// being a translation of English. The Chinese sentences are written in
/// Chinese, so they have no article, no capital letters and no "and", and a
/// test that compared them character by character with the English ones
/// would be testing the wrong thing.

///|
/// The English reading.
fn en() -> @backend.Lang {
  @backend.Lang::english()
}

///|
/// The Chinese reading.
fn zh() -> @backend.Lang {
  @backend.Lang::chinese()
}

///|
test "a tag that names Chinese is Chinese" {
  assert_eq(@backend.Lang::parse("zh"), zh())
  assert_eq(@backend.Lang::parse("ZH"), zh())
  assert_eq(@backend.Lang::parse("zh-CN"), zh())
  assert_eq(@backend.Lang::parse("zh-Hans"), zh())
  assert_eq(@backend.Lang::parse("zh_Hant"), zh())
  assert_eq(@backend.Lang::parse("cn"), zh())
  assert_eq(@backend.Lang::parse("中文"), zh())
}

///|
test "a tag that does not name Chinese is English" {
  assert_eq(@backend.Lang::parse("en"), en())
  assert_eq(@backend.Lang::parse("en-GB"), en())
  assert_eq(@backend.Lang::parse("fr"), en())
  assert_eq(@backend.Lang::parse(""), en())
  // "zhongwen" begins with the letters of "zh" and is not Chinese. A prefix
  // match rather than an equality match would call it Chinese.
  assert_eq(@backend.Lang::parse("zhongwen"), en())
}

///|
test "the tag a language writes as is the tag it reads" {
  assert_eq(@backend.Lang::parse(@backend.Lang::code(en())), en())
  assert_eq(@backend.Lang::parse(@backend.Lang::code(zh())), zh())
}

///|
test "a name with no Chinese in it is shown in English" {
  // The fallback, and the only rule about it: an empty Chinese name means
  // "this model has no Chinese for it", and the reader gets the English.
  assert_eq(zh().pick("Standing", "立位"), "立位")
  assert_eq(zh().pick("Standing", ""), "Standing")
  assert_eq(en().pick("Standing", "立位"), "Standing")
}

///|
test "every position the model has has a Chinese name" {
  let model = @backend.current_model()
  assert_eq(model.positions.length(), 34)
  for position in model.positions {
    if position.label_zh == "" {
      fail("a position has no Chinese name: " + position.id)
    }
  }
}

///|
test "every position the model has has a Chinese gloss" {
  let model = @backend.current_model()
  for position in model.positions {
    if position.gloss_zh == "" {
      fail("a position has no Chinese gloss: " + position.id)
    }
  }
}

///|
test "every slot the model has has a Chinese name and gloss" {
  let model = @backend.current_model()
  assert_eq(model.slots.length(), 8)
  for slot in model.slots {
    if slot.designation_zh == "" {
      fail("a slot has no Chinese name: " + slot.id)
    }
    if slot.gloss_zh == "" {
      fail("a slot has no Chinese gloss: " + slot.id)
    }
  }
}

///|
test "the Chinese names are the table's own" {
  // Not MAKED's translations of them: the vocabulary belongs to the table,
  // and MAKED's job is to carry it rather than to invent it.
  let model = @backend.current_model()
  assert_eq(model.position_label_in("standing", zh()), "立位")
  assert_eq(model.position_label_in("freedom", zh()), "自由")
  assert_eq(model.slot_designation_in("act", zh()), "行动")
  assert_eq(model.slot_designation_in("occasion", zh()), "处境")
  // And the English names are still the English ones.
  assert_eq(model.position_label_in("standing", en()), "Standing")
  assert_eq(model.slot_designation_in("act", en()), "Action")
}

///|
test "the model carries both languages as data" {
  let model = @backend.current_model()
  let json = model.to_json()
  let positions = json_array(json, "positions")
  assert_true(positions.length() == 34)
  for position in positions {
    if json_str(position, "label_zh") == "" {
      fail("a position travels without its Chinese name")
    }
    if json_str(position, "gloss_zh") == "" {
      fail("a position travels without its Chinese gloss")
    }
  }
  let slots = json_array(json, "slots")
  for slot in slots {
    if json_str(slot, "designation_zh") == "" {
      fail("a slot travels without its Chinese name")
    }
  }
}

///|
test "the model carries the edge names in both languages" {
  let model = @backend.current_model()
  // Every trigger the table fires is named in both languages, and the two
  // names are different: an edge whose Chinese name is its English name is
  // an edge with no Chinese, which is a hole rather than a translation.
  assert_true(model.edges.length() > 40)
  for edge in model.edges {
    if edge.zh == "" {
      fail("an edge has no Chinese name")
    }
    if edge.zh == edge.en {
      fail("an edge's Chinese name is its English name: " + edge.en)
    }
  }
}

///|
test "a model file without Chinese still reads, and shows English" {
  // The compatibility rule, in the shape of the thing it is about: a model
  // written before the Chinese vocabulary existed has no Chinese in it, and
  // a reader asking for Chinese gets the English rather than a blank.
  let json : Json = {
    "format": "maked.model.v1",
    "name": "No Chinese",
    "domains": [],
    "positions": [
      {
        "id": "standing",
        "label": "Standing",
        "gloss": "A person standing.",
        "domain": "",
      },
    ],
    "slots": [
      { "id": "act", "designation": "Action", "gloss": "Doing something." },
    ],
    "rules": [],
    "continuations": [],
    "outcomes": [],
  }
  match @backend.Model::from_json(json) {
    Some(model) => {
      assert_eq(model.position_label_in("standing", zh()), "Standing")
      assert_eq(model.position_gloss_in("standing", zh()), "A person standing.")
      assert_eq(model.slot_designation_in("act", zh()), "Action")
      // And the English is unchanged, which is the whole of the promise: the
      // reader who asked for English got what they got before.
      assert_eq(model.position_label_in("standing", en()), "Standing")
    }
    None => fail("a model without Chinese should still read")
  }
}

///|
test "an outcome is named in both languages" {
  let model = @backend.current_model()
  assert_eq(model.outcome_label_in("moved", en()), "Moved")
  assert_eq(model.outcome_label_in("moved", zh()), "迁")
  assert_eq(model.outcome_label_in("block", zh()), "无路")
  // The one the machine refuses to decide is named in both languages too, and
  // the two are the table's own words rather than a translation of each other.
  assert_eq(model.outcome_label_in("open", en()), "Undecided")
  assert_eq(model.outcome_label_in("open", zh()), "未定")
  // The kind is what the machine matches on, and it does not change with the
  // language: a reader in Chinese and a reader in English are looking at the
  // same five outcomes.
  assert_eq(model.outcome_label_in("moved", zh()).length() > 0, true)
}

///|
test "the domain names are in both languages" {
  let model = @backend.current_model()
  assert_eq(model.domains.length(), 5)
  for domain in model.domains {
    if domain.title_zh == "" {
      fail("a domain has no Chinese name: " + domain.id)
    }
    if domain.role_zh == "" {
      fail("a domain has no Chinese role: " + domain.id)
    }
  }
  assert_eq(model.domain_by_letter("M").unwrap().title_in(zh()), "模型")
}

///|
test "the edge names are looked up by the name the transition carries" {
  let model = @backend.current_model()
  let edge = model.edges[0]
  assert_eq(model.edge_label_in(edge.en, en()), edge.en)
  assert_eq(model.edge_label_in(edge.en, zh()), edge.zh)
  // An edge the model does not have is shown as it was asked for, which is
  // the only honest thing left to show.
  assert_eq(model.edge_label_in("no such edge", zh()), "no such edge")
}

///|
test "a position is found by the name a reader sees" {
  let model = @backend.current_model()
  assert_eq(model.position_id_by_label("Standing"), "standing")
  // And by the Chinese name, which is what a step recorded in Chinese would
  // carry.
  assert_eq(model.position_id_by_label("立位"), "standing")
  // A name the model does not have has no id, and the empty string is the
  // honest answer rather than a guess.
  assert_eq(model.position_id_by_label("no such place"), "")
}

///|
test "a sentence in Chinese uses the Chinese names" {
  let facts = chinese_facts()
  let sentence = @backend.step_sentence(facts, zh())
  assert_true(sentence.contains("立位"))
  assert_true(sentence.contains("自由"))
  assert_true(sentence.contains("行动"))
  assert_true(sentence.contains("模型构建者"))
  // And not the English ones: a sentence that mixed the two vocabularies
  // would read as a machine with two heads.
  assert_true(!sentence.contains("Standing"))
  assert_true(!sentence.contains("Freedom"))
  assert_true(!sentence.contains("Action"))
}

///|
test "the English sentence is the one it was" {
  let facts = chinese_facts()
  let sentence = @backend.step_sentence(facts, en())
  assert_true(sentence.contains("Standing"))
  assert_true(sentence.contains("Freedom"))
  assert_true(sentence.contains("Action"))
  assert_true(sentence.contains("model formulator"))
}

///|
test "the two sentences are not one sentence with a prefix" {
  // The Chinese is written in Chinese: no article on the subject, nothing
  // capitalised, and the two halves joined by a comma rather than by "and".
  let facts = chinese_facts()
  let english = @backend.step_sentence(facts, en())
  let chinese = @backend.step_sentence(facts, zh())
  assert_true(english != chinese)
  assert_true(!chinese.contains(" the "))
  assert_true(!chinese.contains("The "))
  assert_true(!chinese.contains(" and "))
}

///|
test "the Chinese sentence says where the cursor went" {
  let facts = chinese_facts()
  let sentence = @backend.step_sentence(facts, zh())
  assert_true(sentence.contains("光标"))
  assert_true(sentence.contains("数据涡轮"))
}

///|
test "a summary in Chinese counts in Chinese" {
  let facts = chinese_facts()
  let summary = @backend.phase_summary(
    @backend.current_model(),
    [facts, facts],
    "Scattered",
    zh(),
  )
  assert_true(summary.contains("最后"))
  assert_true(summary.contains("两步"))
  assert_true(!summary.contains("The last"))
  assert_true(!summary.contains(" of them "))
}

///|
test "the group state is named in Chinese" {
  // The group vocabulary is fixed, so the Chinese name of a recorded group
  // state is a lookup rather than a guess.
  let english = @backend.group_state_in("Scattered", en())
  assert_eq(english, "Scattered")
  let chinese = @backend.group_state_in("Scattered", zh())
  assert_true(chinese != "")
  assert_true(chinese != "Scattered")
  // A state the table does not have keeps the name it was recorded with.
  assert_eq(@backend.group_state_in("no such state", zh()), "no such state")
}

///|
/// The facts of a step that moved, in both languages.
fn chinese_facts() -> @backend.StepFacts {
  {
    letter: "M",
    domain: "Model",
    role: "the model formulator",
    slot: "Action",
    outcome_kind: "moved",
    position_before: "Standing",
    position_after: "Freedom",
    cursor: "the data turbine",
    source: "drive",
    available: 3,
    role_zh: "模型构建者",
    slot_zh: "行动",
    position_before_zh: "立位",
    position_after_zh: "自由",
    cursor_zh: "数据涡轮",
  }
}
