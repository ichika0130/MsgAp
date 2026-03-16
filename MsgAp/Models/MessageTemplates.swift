// Static content for the Souls-style message builder.
// Templates use %@ as the insertion point for the chosen keyword.

struct KeywordCategory {
    let name: String
    let keywords: [String]
}

let messageTemplates: [String] = [
    "%@ ahead",
    "Likely %@",
    "Beware of %@",
    "Try %@",
    "Praise the %@!",
    "Visions of %@...",
    "Time for %@",
]

let keywordCategories: [KeywordCategory] = [
    KeywordCategory(
        name: "Enemies",
        keywords: ["enemy", "boss", "dog", "ambush", "sniper"]
    ),
    KeywordCategory(
        name: "People",
        keywords: ["friend", "merchant", "liar", "thief", "fatty"]
    ),
    KeywordCategory(
        name: "Environment",
        keywords: ["hidden path", "trap", "shortcut", "dead end", "cliff", "safe zone", "gorgeous view"]
    ),
    KeywordCategory(
        name: "Items",
        keywords: ["treasure", "chest", "weapon", "magic", "message"]
    ),
    KeywordCategory(
        name: "Concepts",
        keywords: ["danger", "death", "despair", "joy", "rolling", "jumping"]
    ),
]
