import Foundation

// MARK: - Diversity Reranker (Phase 9A)
// MMR (Maximal Marginal Relevance) reranking for category diversity.
// Ensures the final candidate set sent to the LLM isn't "5 cafés and 3 restaurants"
// but a balanced mix of categories that makes remixes genuinely different.
// Algorithm: greedily select candidates that balance score vs. dissimilarity to already-selected.
// North star doc: "diversified reranking / MMR-style logic" for exploration/exploitation tradeoff.

struct DiversityReranker {

    /// MMR-based reranking: greedily selects candidates that balance score vs. diversity.
    /// - lambda: weight for relevance vs. diversity (0.7 = favor quality, 0.5 = favor diversity for remix)
    /// - topK: number of candidates to select
    /// - recentGeneratedCategories: categories from recent generations (for cross-run diversity)
    /// - Returns: up to topK candidates ordered by MMR selection
    static func rerank(
        scored: [ScoredCandidate],
        lambda: Double = 0.7,
        topK: Int = 8,
        recentGeneratedCategories: [String] = []
    ) -> [ScoredCandidate] {
        guard !scored.isEmpty else { return [] }
        guard scored.count > topK else { return scored }

        var selected: [ScoredCandidate] = []
        var remaining = scored  // already sorted by composite DESC from CandidateScorer

        // Seed the "already selected" categories with recent cross-run history.
        // This makes MMR treat recently generated categories as if they're already in the set,
        // pushing the algorithm to pick different categories first.
        let recentCatSet = Set(recentGeneratedCategories.suffix(3))

        // First pick: always the highest-scored candidate
        let first = remaining.removeFirst()
        selected.append(first)

        // Greedy MMR selection
        while selected.count < topK && !remaining.isEmpty {
            var bestIndex = 0
            var bestMMR = -Double.infinity

            for (i, candidate) in remaining.enumerated() {
                let relevance = candidate.score.composite

                // Max category similarity to any already-selected candidate
                let maxSimSelected = selected.map { sel in
                    categorySimilarity(candidate, sel)
                }.max() ?? 0.0

                // Cross-run category penalty: if this candidate's category was recently generated,
                // treat it as partially similar to an already-selected item
                let candidateCat = CandidateScorer.inferCategory(from: candidate.candidate.types.map { $0.lowercased() })
                let crossRunSim = recentCatSet.contains(candidateCat) ? 0.6 : 0.0

                let maxSim = max(maxSimSelected, crossRunSim)

                // MMR = λ × relevance - (1-λ) × max_similarity
                let mmrScore = lambda * relevance - (1.0 - lambda) * maxSim

                if mmrScore > bestMMR {
                    bestMMR = mmrScore
                    bestIndex = i
                }
            }

            selected.append(remaining.remove(at: bestIndex))
        }

        return selected
    }

    // MARK: - Category Similarity
    // Same inferred category = 1.0, related category = 0.5, different = 0.0.
    // Uses CandidateScorer.inferCategory(from:) — already static and public.

    private static func categorySimilarity(
        _ a: ScoredCandidate,
        _ b: ScoredCandidate
    ) -> Double {
        let catA = CandidateScorer.inferCategory(from: a.candidate.types.map { $0.lowercased() })
        let catB = CandidateScorer.inferCategory(from: b.candidate.types.map { $0.lowercased() })

        if catA == catB { return 1.0 }
        if areRelated(catA, catB) { return 0.5 }
        return 0.0
    }

    // MARK: - Related Category Pairs
    // Categories that are conceptually similar but not identical.
    // Penalized at 0.5 instead of 1.0 to allow some thematic clustering while avoiding monotony.

    private static func areRelated(_ a: String, _ b: String) -> Bool {
        let relatedPairs: Set<Set<String>> = [
            ["coffee", "food"],        // both involve sitting and consuming
            ["food", "market"],        // both food-related
            ["nature", "other"],       // parks and misc outdoor
            ["nightlife", "food"],     // bars often serve food
            ["culture", "bookstore"],  // both intellectual/cultural
            ["culture", "music"],      // both arts/cultural
            ["shopping", "bookstore"], // both retail
            ["shopping", "music"],     // both retail (record stores)
        ]
        return relatedPairs.contains([a, b])
    }
}
