/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

/// Flags to enable access rights when the user password is used
enum PdfAccessFlags {
  /// Print the document
  Print,

  /// Modify the contents of the document by operations other
  /// than [Annotate], [Interactive] and [Assemble]
  Modify,

  /// Copy or otherwise extract text and graphics from the document,
  /// including extracting text and graphics
  Copy,

  /// Add or modify text annotations, fill in interactive form fields
  Annotate,

  /// Fill in existing interactive form fields (including signature fields)
  Interactive,

  /// Support of accessibility to users with disabilities
  Accessibility,

  /// Assemble the document: insert, rotate, or delete pages and create
  /// bookmarks or thumbnail images
  Assemble,

  /// Print the document to a representation from which a faithful
  /// digital copy of the PDF content could be generated. When this bit
  /// is clear (and [Print] is set), printing is limited to a low-level
  /// representation of the appearance, possibly of degraded quality.
  HighQualityPrint
}
