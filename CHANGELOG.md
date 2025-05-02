# Changelog

## 3.3.11

- Fix compressed objects parsing
- Update dependencies

## 3.3.10

- Use secure random number generator.
- Pdf 3.11.2 compatibility
- Add wasm compatibility

## 3.3.9

- Fix page change if content is intirect array

## 3.3.8

- Improve crossref parser

## 3.3.7

- Fix PNG predictor for 1 bit images

## 3.3.6

- Fix Compressed stream decompression

## 3.3.5

- Update dependencies
- Refactor AES encryption implementation
- Add pre and post content streams for protected contents
- Improve form management

## 3.3.4

- Add Document Appender
- Add form field parser
- Add pre and post content streams for protected contents

## 3.3.3

- Fix merging PDF with missing objects

## 3.3.2

- Implement tools to merge multiple PDF

## 3.3.1

- Fix loading a document with obj not on end of line

## 3.3.0

- Improve Signature range offset
- Add Compatibility with dart_pdf 3.10.0
- Force some objects to be direct
- Reuse the same objects for Pages and Catalog

## 3.2.9

- Fix crossref parsing issue

## 3.2.8

- Fix utf8 decoding issue

## 3.2.7

- Fix loading ZLib compressed data on web

## 3.2.6

- Implement ASCIIHex and LZW filters decoding
- Fix issue reading some PDF documents

## 3.2.5

- Add document parsing API

## 3.2.4

- Implement PdfPageLabels loading
- Fix some lint issues
- Correctly parse nested MediaBox

## 3.2.3

- Fix parsing files with mixed new-lines
- Fix parsing pages with no /Resources
- Fix object parsing with mixed new-lines
- Implement Compressed objects parser
- Add support for DecodeParms

## 3.2.2

- Fix parsing of some document

## 3.2.1

- Remove debug log

## 3.2.0

- Update dependencies

## 3.1.0

- Allow inplace page edit
- Remove useless override
- Add PdfDictStream parser
- Add ASCII85 Decoder
- Add Compressed XREF parser
- Add Timestamp support
- Add Pdf Document signature verification
- Use public pkcs7 package

## 3.0.2

- Add an option to save the graphic context
- Fix x509 serial number again
- Fix Issuer copy

## 3.0.1

- Add missing export for the cert library
- Remove duplicate certificate
- Fix x509 serial number

## 3.0.0

- Implement null-safety
- Add Full support for PKCS#7 signatures

## 2.0.1

- Update dependencies

## 2.0.0

- Add a PDF parser
- Add signature permissions
- Add support for sha384 and sha512 signature digests
- Add support for PKCS#7 signatures

## 1.0.5

- Migrate to Pdf 1.13.0
- Don't use library style anymore
- Remove asn1lib dependency

## 1.0.4

- Update dependencies
- Update analysis options

## 1.0.3

- Add more public api documentation

## 1.0.2

- Add examples and update the README

## 1.0.1

- Fixes for pdf 1.6.0

## 1.0.0

- Initial version
