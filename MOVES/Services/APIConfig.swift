import Foundation

// MARK: - API Configuration
// Reads keys from Secrets.plist (gitignored — never committed).
// To run locally: copy Secrets.plist.template → Secrets.plist and fill in your keys.

struct APIConfig {
    static let shared = APIConfig()

    let googlePlacesKey: String
    let openAIKey: String
    let eventbriteKey: String

    private init() {
        // Load from Secrets.plist (gitignored)
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let gKey = dict["GOOGLE_PLACES_API_KEY"] as? String, !gKey.isEmpty,
           let oKey = dict["OPENAI_API_KEY"] as? String, !oKey.isEmpty {
            self.googlePlacesKey = gKey
            self.openAIKey = oKey
            self.eventbriteKey = (dict["EVENTBRITE_KEY"] as? String) ?? ""
            print("[APIConfig] ✅ Keys loaded from Secrets.plist")
            if self.eventbriteKey.isEmpty {
                print("[APIConfig] ℹ️ No Eventbrite key — events will be skipped")
            }
            return
        }

        // No keys found — app will fail gracefully on API calls.
        // Add your keys to Secrets.plist (see Secrets.plist.template).
        self.googlePlacesKey = ""
        self.openAIKey = ""
        self.eventbriteKey = ""
        print("[APIConfig] ⚠️ No API keys found — add them to Secrets.plist")
    }

    var hasValidKeys: Bool {
        !googlePlacesKey.isEmpty && !openAIKey.isEmpty
    }
}
