import Foundation

// MARK: - NeuroTopicCatalog
/// Mirrors Android `NeuroTopicCatalog.kt` for onboarding + content preferences.
enum NeuroTopicCatalog {
    struct Category: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let systemImage: String
        let topics: [String]
    }

    static let categories: [Category] = [
        Category(name: "Gaming", systemImage: "gamecontroller.fill", topics: [
            "Gaming", "Minecraft", "Fortnite", "GTA", "Call of Duty",
            "Valorant", "League of Legends", "Pokemon", "Nintendo",
            "PlayStation", "Xbox", "PC Gaming", "Esports", "Speedruns",
            "Game Reviews", "Indie Games", "Retro Gaming", "Mobile Games",
            "Roblox", "Apex Legends", "FIFA"
        ]),
        Category(name: "Music", systemImage: "music.note", topics: [
            "Music", "Pop Music", "Hip Hop", "R&B", "Rock", "Metal",
            "Jazz", "Classical", "Electronic", "EDM", "Lo-Fi", "K-Pop",
            "J-Pop", "Country", "Indie Music", "Music Production",
            "Guitar", "Piano", "Singing", "Music Theory", "Album Reviews",
            "Concerts", "DJ"
        ]),
        Category(name: "Technology", systemImage: "laptopcomputer", topics: [
            "Technology", "Programming", "Coding", "Web Development",
            "App Development", "AI", "Machine Learning", "Cybersecurity",
            "Linux", "Apple", "Android", "Smartphones", "Laptops",
            "PC Building", "Tech Reviews", "Gadgets", "Software",
            "Cloud Computing", "Blockchain", "Crypto", "Startups"
        ]),
        Category(name: "Entertainment", systemImage: "film", topics: [
            "Movies", "TV Shows", "Netflix", "Anime", "Marvel", "DC",
            "Star Wars", "Disney", "Comedy", "Stand-up Comedy", "Drama",
            "Horror", "Sci-Fi", "Documentary", "Film Analysis",
            "Movie Reviews", "Behind the Scenes", "Celebrities",
            "Award Shows", "Trailers", "Fan Theories"
        ]),
        Category(name: "Education", systemImage: "book.fill", topics: [
            "Science", "Physics", "Chemistry", "Biology", "Mathematics",
            "History", "Geography", "Psychology", "Philosophy",
            "Economics", "Finance", "Investing", "Business", "Marketing",
            "Language Learning", "English", "Spanish", "Study Tips",
            "College", "University", "Tutorials"
        ]),
        Category(name: "Health & Fitness", systemImage: "heart.fill", topics: [
            "Fitness", "Workout", "Gym", "Yoga", "Running", "CrossFit",
            "Bodybuilding", "Weight Loss", "Nutrition", "Healthy Eating",
            "Mental Health", "Meditation", "Self Improvement",
            "Productivity", "Motivation", "Sports", "Basketball",
            "Football", "Soccer", "MMA", "Boxing", "Tennis", "Golf"
        ]),
        Category(name: "Lifestyle", systemImage: "leaf.fill", topics: [
            "Cooking", "Recipes", "Baking", "Food", "Restaurants",
            "Travel", "Vlogging", "Daily Vlog", "Fashion", "Style",
            "Beauty", "Skincare", "Home Decor", "Interior Design", "DIY",
            "Crafts", "Gardening", "Pets", "Dogs", "Cats", "Cars",
            "Motorcycles", "Photography"
        ]),
        Category(name: "Creative", systemImage: "paintbrush.fill", topics: [
            "Art", "Drawing", "Painting", "Digital Art", "Animation",
            "3D Modeling", "Graphic Design", "Video Editing", "Filmmaking",
            "Photography", "Music Production", "Writing", "Storytelling",
            "Architecture", "Fashion Design", "Crafts", "Woodworking",
            "Sculpture"
        ]),
        Category(name: "Science & Nature", systemImage: "globe.americas.fill", topics: [
            "Space", "Astronomy", "NASA", "Physics", "Nature", "Animals",
            "Wildlife", "Ocean", "Marine Life", "Environment", "Climate",
            "Geology", "Paleontology", "Dinosaurs", "Engineering",
            "Inventions", "Experiments"
        ]),
        Category(name: "News & Current Events", systemImage: "newspaper.fill", topics: [
            "News", "Politics", "World News", "Tech News", "Sports News",
            "Entertainment News", "Business News", "Analysis",
            "Commentary", "Podcasts", "Interviews", "Debates",
            "Current Events"
        ])
    ]

    static let blockSuggestions = [
        "ASMR", "Unboxing", "Reaction", "Vlogs", "News", "Politics",
        "Gaming", "clickbait", "drama", "gossip", "challenge", "family vlog"
    ]
}
