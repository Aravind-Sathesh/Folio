/// "Finance/Invoices" -> "Finance › Invoices", the way the UI names folders.
func folderDisplay(_ relativeFolder: String) -> String {
    relativeFolder.split(separator: "/").joined(separator: " › ")
}

extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
}

func reviewCountText(_ count: Int) -> String {
    count == 1 ? "1 file needs review" : "\(count) files need review"
}
