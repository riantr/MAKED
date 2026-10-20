///|
/// The version of MAKED.
///
/// The number in `moon.mod`, kept here because the module's own version is
/// not available to the code it contains, and the agent's server has to
/// report one: an MCP client asks the server what it is before it asks it
/// for anything.
///
/// A test reads `moon.mod` and checks the two against each other, so a
/// release that bumps one and not the other is caught rather than shipped
/// with two versions in it.
pub const MAKED_VERSION : String = "0.1.7"
