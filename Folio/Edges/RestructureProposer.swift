import Foundation

struct RestructureProposal: Sendable {
    var items: [RestructureItem]
    var questions: [RestructureQuestion]
}

/// Asks the restructure model where every file should go, in batches, and validates each answer before it is kept.
struct RestructureProposer: Sendable {
    let client: OllamaClient
    let paths: FolioPaths
    var model: ModelSpec = .restructure

    /// `planned` are folders other items already propose (so a second pass sees them). Questions stop at `maxQuestions`.
    func propose(_ items: [RestructureItem], answers: [RestructureAnswer] = [], planned: Set<String> = [], maxQuestions: Int = restructureMaxQuestions,
                 progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> RestructureProposal {
        var result = items
        var questions: [RestructureQuestion] = []
        var virtual = planned
        let onDisk = listFolders(in: paths.documents)
        var done = 0
        for batch in batches(Array(items.indices)) {
            let entries = batch.enumerated().map { (id: $0.offset + 1, item: items[$0.element]) }
            let folders = Set(onDisk).union(virtual).sorted()
            let answer: RestructureAnswerJSON
            do {
                answer = try await client.chat(model, system: RestructurePrompt.system(maxQuestions: max(0, maxQuestions - questions.count)),
                                               user: RestructurePrompt.user(entries: entries, folders: folders, answers: answers, documents: paths.documents),
                                               schema: restructureSchema, as: RestructureAnswerJSON.self)
            } catch OllamaError.badResponse {
                for index in batch { result[index].note = "The model gave no usable answer" }
                done += batch.count
                progress(done, items.count)
                continue
            }
            for move in answer.moves {
                guard let index = batch.indices.contains(move.id - 1) ? batch[move.id - 1] : nil else { continue }
                apply(move, to: &result[index], virtual: virtual)
            }
            virtual.formUnion(plannedFolders(batch.map { result[$0] }))
            for question in answer.questions where questions.count < maxQuestions && question.options.count >= 2 {
                let affected = question.ids.compactMap { batch.indices.contains($0 - 1) ? items[batch[$0 - 1]].path : nil }
                guard !affected.isEmpty else { continue }
                questions.append(RestructureQuestion(id: questions.count + 1, text: question.text, options: Array(question.options.prefix(4)), affected: affected))
            }
            done += batch.count
            progress(done, items.count)
        }
        return RestructureProposal(items: result, questions: questions)
    }

    private func apply(_ move: RestructureAnswerJSON.Move, to item: inout RestructureItem, virtual: Set<String>) {
        let source = URL(fileURLWithPath: item.path)
        switch validate(proposal: Proposal(name: move.name, folder: move.folder), source: source, paths: paths, virtualFolders: virtual) {
        case .success(let valid):
            item.proposedFolder = relativeFolder(of: valid.destination.path, in: paths.documents)
            item.proposedName = valid.name
            item.reason = move.reason
            item.note = nil
        case .failure(let reason):
            // An unusable proposal means "leave it", never a guess.
            item.proposedFolder = nil
            item.proposedName = nil
            item.note = plainReason(reason)
        }
    }
}
