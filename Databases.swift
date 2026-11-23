import SwiftUI
import Vision
import VisionKit

struct FoodRecognition: Identifiable {
    let id = UUID()
    let name: String
    let searchTerm: String
    let confidence: Float
}

/// Reconnaissance locale via Vision : l'image reste sur l'appareil.
enum OnDeviceFoodRecognition {
    private static let foodLabels: [String: (name: String, search: String)] = [
        "pizza": ("Pizza", "pizza"),
        "cheeseburger": ("Cheeseburger", "hamburger"),
        "hamburger": ("Hamburger", "hamburger"),
        "hotdog": ("Hot-dog", "hot-dog"),
        "hot dog": ("Hot-dog", "hot-dog"),
        "french fries": ("Frites", "frites"),
        "mashed potato": ("Purée de pommes de terre", "purée"),
        "baked potato": ("Pomme de terre au four", "pomme de terre"),
        "spaghetti": ("Spaghetti", "pâtes"),
        "carbonara": ("Pâtes à la carbonara", "pâtes"),
        "pasta": ("Pâtes", "pâtes"),
        "noodle": ("Nouilles", "nouilles"),
        "ramen": ("Ramen", "ramen"),
        "sushi": ("Sushi", "sushi"),
        "sashimi": ("Sashimi", "sashimi"),
        "burrito": ("Burrito", "burrito"),
        "taco": ("Tacos", "tacos"),
        "guacamole": ("Guacamole", "guacamole"),
        "salad": ("Salade composée", "salade"),
        "soup": ("Soupe", "soupe"),
        "sandwich": ("Sandwich", "sandwich"),
        "bread": ("Pain", "pain"),
        "french loaf": ("Baguette", "baguette"),
        "bagel": ("Bagel", "bagel"),
        "croissant": ("Croissant", "croissant"),
        "pretzel": ("Bretzel", "bretzel"),
        "waffle": ("Gaufre", "gaufre"),
        "pancake": ("Pancakes", "pancake"),
        "omelet": ("Omelette", "omelette"),
        "fried egg": ("Œuf au plat", "œuf"),
        "boiled egg": ("Œuf dur", "œuf"),
        "apple": ("Pomme", "pomme"),
        "granny smith": ("Pomme", "pomme"),
        "banana": ("Banane", "banane"),
        "strawberry": ("Fraise", "fraise"),
        "orange": ("Orange", "orange"),
        "lemon": ("Citron", "citron"),
        "pineapple": ("Ananas", "ananas"),
        "watermelon": ("Pastèque", "pastèque"),
        "broccoli": ("Brocoli", "brocoli"),
        "cauliflower": ("Chou-fleur", "chou-fleur"),
        "cucumber": ("Concombre", "concombre"),
        "zucchini": ("Courgette", "courgette"),
        "mushroom": ("Champignon", "champignon"),
        "corn": ("Maïs", "maïs"),
        "bell pepper": ("Poivron", "poivron"),
        "carrot": ("Carotte", "carotte"),
        "tomato": ("Tomate", "tomate"),
        "steak": ("Steak", "bœuf"),
        "beef": ("Bœuf", "bœuf"),
        "chicken": ("Poulet", "poulet"),
        "roast chicken": ("Poulet rôti", "poulet"),
        "salmon": ("Saumon", "saumon"),
        "fish": ("Poisson", "poisson"),
        "shrimp": ("Crevettes", "crevette"),
        "prawn": ("Crevettes", "crevette"),
        "cheese": ("Fromage", "fromage"),
        "yogurt": ("Yaourt", "yaourt"),
        "ice cream": ("Glace", "glace"),
        "chocolate cake": ("Gâteau au chocolat", "gâteau au chocolat"),
        "cheesecake": ("Cheesecake", "cheesecake"),
        "pudding": ("Crème dessert", "crème dessert"),
        "rice": ("Riz", "riz")
    ]

    static func recognize(_ image: UIImage) async throws -> [FoodRecognition] {
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw AIError.bad("Impossible de lire cette photo.")
        }

        let raw = try await Task.detached(priority: .userInitiated) { () throws -> [(String, Float)] in
            let handler = VNImageRequestHandler(data: data, options: [:])
            var predictions: [(String, Float)] = []

            // iOS 17 Vision : isole les objets de premier plan, puis classe chaque masque.
            // Cette segmentation est générique, pas une segmentation sémantique d'ingrédients.
            let instanceRequest = VNGenerateForegroundInstanceMaskRequest()
            if (try? handler.perform([instanceRequest])) != nil,
               let observation = instanceRequest.results?.first {
                for instance in Array(observation.allInstances).prefix(6) {
                    guard let masked = try? observation.generateMaskedImage(
                        ofInstances: IndexSet(integer: instance),
                        from: handler,
                        croppedToInstancesExtent: true
                    ) else { continue }
                    let classifier = VNClassifyImageRequest()
                    if (try? VNImageRequestHandler(cvPixelBuffer: masked, options: [:]).perform([classifier])) != nil {
                        predictions.append(contentsOf: (classifier.results ?? []).prefix(5).map {
                            ($0.identifier, $0.confidence)
                        })
                    }
                }
            }

            // Classification de l'image entière en complément et en solution de repli.
            let wholeImage = VNClassifyImageRequest()
            try handler.perform([wholeImage])
            predictions.append(contentsOf: (wholeImage.results ?? []).prefix(15).map {
                ($0.identifier, $0.confidence)
            })
            return predictions
        }.value

        var seen = Set<String>()
        return raw.compactMap { identifier, confidence in
            let key = identifier.lowercased().replacingOccurrences(of: "_", with: " ")
            guard confidence >= 0.025,
                  let match = foodLabels[key] ?? foodLabels.first(where: { key.contains($0.key) })?.value,
                  seen.insert(match.search).inserted else { return nil }
            return FoodRecognition(name: match.name, searchTerm: match.search, confidence: confidence)
        }.prefix(5).map { $0 }
    }
}

