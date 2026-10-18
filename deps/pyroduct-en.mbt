///|
/// English renderings of the pyroduct vocabulary.
///
/// pyroduct is a Chinese-language model: `label()` is the *source layer* -- the
/// wording taken from the original text, kept verbatim so every state can be
/// traced back. That layer is deliberately not translated here; this file adds
/// a parallel English rendering alongside it, so an English-only surface can
/// read the model without touching the source wording.
///
/// Everything here is presentation vocabulary. Nothing in this file
/// participates in the state machine: the 34 states, 53 transitions, 11 phases
/// and 8 slots, and every `exitable` / `after_open` / `step` decision are
/// unchanged. A mismatch here can only mislabel a transition, never invent
/// one.
///
/// ## Staging
///
/// `.mooncakes/` is gitignored -- it is a dependency cache, not source -- so
/// `build.ps1` copies this file into
/// `.mooncakes/riantr/pyroduct/src/en.mbt` before compiling. This file is the
/// source of truth; the copy is a build artefact. Editing the copy directly is
/// pointless, because `moon update` refetches the package and drops it.

///|
/// The English name of a subject state.
///
/// Paired with `label()`, which stays the Chinese source wording.
pub fn SubjectState::en_label(self : SubjectState) -> String {
  match self {
    NoPast => "No Past"
    NoFuture => "Aimless"
    Standing => "Standing"
    Freedom => "Freedom"
    Urgency => "Urgency"
    Alienation => "Alienation"
    Emptiness => "Emptiness"
    Busyness => "Busyness"
    Selfhood => "Selfhood"
    Weaving => "Weaving"
    Choosing => "Choosing"
    Encounter => "Encounter"
    Opening => "Opening"
    Evil => "Evil"
    Shame => "Shame"
    Guilt => "Guilt"
    Binding => "Binding"
    Secret => "Secret"
    Suffering => "Suffering"
    Loss => "Loss"
    Idol => "Idol"
    Ordered => "Order"
    Sublime => "Sublime"
    Passion => "Passion"
    Honor => "Honor"
    Awe => "Awe"
    Habit => "Habit"
    Reflection => "Reflection"
    Dizziness => "Dizziness"
    Harmony => "Harmony"
    Model => "Model"
    Marking => "Marking"
    Discipline => "Discipline"
    Tranquility => "Tranquility"
  }
}

///|
/// An English rendering of the textual basis for a state.
///
/// `gloss()` stays the Chinese source sentence; this is its English counterpart.
pub fn SubjectState::en_gloss(self : SubjectState) -> String {
  match self {
    NoPast => "A person without memory has no past."
    NoFuture => "A person living in dull confusion cares nothing for the future."
    Standing =>
      "The person stands with both feet on the ground, one foot set upon the past and one reaching toward the future; dealing with the past and preparing for the future is what must be done now."
    Freedom =>
      "Dealing and preparing rest on the freedom of action; freedom is a rejoinder, and this rejoinder is creation, founding one's own time and space."
    Urgency =>
      "A person is born dying; what arises from this finite-yet-boundless nature of time is a sense of urgency."
    Alienation =>
      "The whole expanse of heaven is his to roam, yet the space he occupies amounts to a mere few feet; what arises from this infinite-yet-bounded nature of space is a sense of alienation."
    Emptiness =>
      "When urgency and alienation blend into one another, the person's experience of freedom turns into an emptiness that is everywhere."
    Busyness => "The person now has to be busy, and the world becomes vivid because of it."
    Selfhood =>
      "Within continuity the person discovers an independent self; this self is not destroyed by the changes around it, and continually draws in and settles down whatever it undergoes."
    Weaving =>
      "Everything past turns to residue, trailing behind as a dotted line slowly fading; on contact with the future some of it is pulled back, and old and new weave into a picture, as though holding infinite possibility."
    Choosing =>
      "Amid infinite possibility the person is not indiscriminate: which piece of ground is more solid, which relation more enduring?"
    Encounter =>
      "Unavoidably, the person encounters the other; for the solitary, the encounter begins as surprise, is followed by doubt, and they linger with one another."
    Opening =>
      "One cannot be sure the other is the same as oneself, but what harm is there in making a goodwill assumption; tremblingly, one opens one's arms to one another."
    Evil =>
      "When what one touches is hard and cold, the person recoils at once; a new picture arises -- this is the sense of evil; space contracts and a frontier appears."
    Shame =>
      "Facing this turn of events, the person takes the responsibility as their own, and shame arises."
    Guilt =>
      "When shame fills the emptiness, the person loses freedom for the first time; this is guilt."
    Binding =>
      "So the person binds themselves, and must once more examine the past; what was clear and what was unclear come before the eyes."
    Secret =>
      "He is eager to rid himself of this burden, and there is nothing to do but avoid it; from then on he no longer mentions those things he deliberately wishes to forget -- a secret."
    Suffering =>
      "If the coming moment recklessly stings the scar, suffering lies before the eyes; suffering is hard to end, for it was caused by the person themselves."
    Loss =>
      "The result of suffering is a universal loss in the next moment; as his world sinks day by day, the person begins to blame himself."
    Idol =>
      "To regain freedom, he strives to cut off his ties to the past; the idol first appears as a goal, and the person calls the idol up from within."
    Ordered =>
      "Because of the idol, everything begins to have order, an order promulgated by the idol; suffering vanishes as if by miracle, and the world regains a firmer footing."
    Sublime =>
      "The person sees glory in the idol, and when he becomes aware of being lit through by that glory, the sublime arises of its own accord."
    Passion =>
      "In pursuit of more joy, he keeps to the path he was on, and each next moment arrives quicker for what he gains; the person is then enveloped in passion."
    Honor => "When the idol grants him reward, honor is born."
    Awe => "Otherwise, there is awe."
    Habit =>
      "The person passes a good while in this honor and awe; when he grows accustomed to what he bears, he cools once more and examines the past."
    Reflection =>
      "Chasing all manner of sensations, he had nearly forgotten that first goal; is the self a string of sensations or something else? The person's world becomes precarious again."
    Dizziness =>
      "He begins trying every method to see his own path more clearly; but time does not pause, and the next moment and the threat of death keep welling up, and in this dizziness the person reaches for his own harmony."
    Harmony => "This harmony is the balance of past and future."
    Model =>
      "When he seeks a goal for that harmony, the person takes whatever in the other is useful to him as his own model."
    Marking =>
      "He marks the good and the bad to guide the orientation of the next moment, setting waymarks ahead and avoiding the reefs as far as possible; and every change renders the previous moment's map invalid."
    Discipline =>
      "The frontier keeps widening, the reefs are no longer isolated; the person tries to endure a temporary pain in exchange for greater freedom, and the activity of removing those reefs is discipline."
    Tranquility =>
      "Fewer and fewer reefs, a wider and wider frontier, the person's freedom lifted once more; suffering lightens, the reefs cease to be reefs, and all that the eye sees and the finger points to is nothing but a piece of light."
  }
}

///|
/// The English name of a phase.
pub fn Phase::en_label(self : Phase) -> String {
  match self {
    Natural => "Natural"
    Release => "The Arising of Freedom"
    Becoming => "Selfhood and Choosing"
    Otherness => "Encounter with the Other"
    Bondage => "Evil, Shame, Guilt, Self-binding"
    Anguish => "Suffering and Loss"
    Idolatry => "Idol and Ground"
    Glory => "Sublime, Passion, Honor, Awe"
    Recollection => "Reflection"
    Upbringing => "The Way of Discipline"
    Serenity => "Tranquility"
  }
}

///|
/// An English rendering of a trigger's source wording.
///
/// These are what a transition reads as in a history line, so they carry the
/// same weight as the state glosses.
pub fn Trigger::en_label(self : Trigger) -> String {
  match self {
    TakeStand =>
      "Both feet on the ground, one set upon the past and one reaching toward the future"
    ActInFreedom =>
      "Freedom of action is what dealing and preparing rest on; freedom is a rejoinder against history and frontier, and this rejoinder is creation"
    FeelFinitude => "The urgency arising from the finite-yet-boundless nature of time"
    FeelBoundlessness =>
      "The alienation arising from the infinite-yet-bounded nature of space"
    FuseFeelings =>
      "Urgency and alienation blend, and the experience of freedom turns into an emptiness everywhere"
    MustBeBusy => "The person has to be busy, and the world becomes vivid"
    KeepContinuity =>
      "Activity does not pause for a moment; within continuity the person discovers an independent self"
    Deposit => "Continually drawing in and settling down whatever is undergone"
    TurnToResidue =>
      "Everything past becomes residue, trailing behind as a dotted line slowly fading"
    TouchFuture => "Contact with the future; some of it is pulled back again"
    Interweave =>
      "Old and new weave into a picture, changing with every new next moment"
    ChooseMoreLasting =>
      "Choosing a more enduring relation among all possible connections"
    MeetOther => "Unavoidably, the person encounters the other"
    Surprise => "At first, surprise"
    Doubt => "Then doubt follows"
    Linger => "They linger with one another"
    GoodFaith =>
      "One cannot be sure the other is like oneself, but what harm is there in a goodwill assumption"
    OpenArms => "Tremblingly, one opens one's arms to one another"
    Complexify => "That very goal is casually complicated"
    ColdHard =>
      "What is touched is hard and cold, and the person recoils at once"
    AttributeSelf =>
      "Facing this turn of events, the person takes the responsibility as their own"
    FillEmptiness =>
      "Shame fills the emptiness, and the person loses freedom for the first time"
    BindSelf => "So the person binds themselves"
    Avoid => "What else can one do but avoid it"
    Sting => "The coming next moment recklessly stings the scar"
    BlameSelf =>
      "As his world sinks day by day, the person begins to blame himself"
    CutPast => "To regain freedom, he strives to cut off his ties to the past"
    SummonIdol => "The person calls the idol up from within"
    EnactOrder => "Everything begins to have order, promulgated by the idol"
    AbsorbGlory => "When he becomes aware of being lit through by that glory"
    SeekMoreJoy => "In pursuit of more, he keeps to the path he was on"
    Reward => "When the idol grants him reward"
    Dread => "Otherwise, there is awe"
    Habituate => "When he grows accustomed to what he bears"
    CoolDown => "He cools once more and examines the past"
    DoubtOneself => "Is the self a string of sensations, or something else"
    TryMethods =>
      "He begins trying every method, to make his own path clearer to himself"
    SeekBalance => "In the dizziness the person reaches for his own harmony"
    SeekGoal => "When he seeks a goal for harmony"
    TakeModel => "Taking whatever in the other is useful as one's own model"
    Approximate => "He tries to approach the goal, trying again and again"
    MarkGoodBad =>
      "He marks the good and the bad, to guide the orientation of the next moment"
    RedrawMap =>
      "Every change of the next moment invalidates the previous map, and the marking must be redone"
    WidenFrontier =>
      "As the frontier widens, the surroundings grow clearer and the reefs are no longer isolated"
    Endure =>
      "He tries to endure a temporary pain in exchange for greater freedom"
    RemoveReefs => "The activity of removing these reefs is discipline"
    Ascend =>
      "Fewer reefs, a wider frontier, and the person's freedom is lifted once more"
    WaitNext => "All he needs to do is wait for the next moment to arrive"
    ReopenByHorizon =>
      "The frontier keeps widening; a new next moment invalidates the map and the whole cycle reopens"
  }
}

///|
/// The English designation of a drive slot.
///
/// Paired with `designation()`, which names the structural relation in Chinese.
pub fn Slot::en_designation(self : Slot) -> String {
  match self {
    Occasion => "Occasion"
    Orientation => "Orientation"
    Antecedent => "Anticipation"
    Act => "Action"
    Feedback => "Feedback"
    Hold => "Holding"
    CoBeing => "Co-being"
    Unveil => "Unveiling"
  }
}

///|
/// An English rendering of a slot's structural gloss.
pub fn Slot::en_gloss(self : Slot) -> String {  match self {
    Occasion =>
      "A giving not initiated by the subject yet moves them: time and space, necessity, and everything before the sting"
    Orientation => "The position where a goal is set, complicated, or replaced"
    Antecedent =>
      "Contact with the future, waiting for the next moment, trying again and again -- moving with expectation, but offering no probability"
    Act =>
      "The push that has an action in the source: binding oneself, cutting off the past, enduring, removing reefs"
    Feedback =>
      "A return from the environment, an idol, or one's own prior position: reward, deterrence, promulgation, widening frontier"
    Hold =>
      "What does not move: drawing in and settling down, interweaving old and new, habit, surprise, doubt, lingering"
    CoBeing =>
      "The dimension of the other: encounter, the goodwill assumption, opening one's arms to one another"
    Unveil =>
      "Unveiling and concealing (R3): cooling down, questioning what the self is, the frontier reopening"
  }
}

///|
/// An English rendering of an outcome's receipt label.
///
/// Paired with `Outcome::label()`, whose five values are the vocabulary the
/// loop engine reasons about: `Moved` and `Held` are progress, `Undecided` is
/// the table declining to choose, `Converge` is several triggers arriving at
/// one target, and `No Edge` is a gap in the table.
pub fn Outcome::en_label(self : Outcome) -> String {
  match self {
    Moved(_, _) => "Moved"
    Held(_, _) => "Held"
    Open(_) => "Undecided"
    Same(_, _, _) => "Converge"
    Block(_) => "No Edge"
  }
}
