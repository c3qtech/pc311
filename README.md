# Pdf encryption library for dart / flutter

## Generate an encrypted document

```dart
final pdf = Document();

// Declare the encryption options
pdf.document.encryption = PdfEncryptionAES(
  pdf.document,
  user: '1234', // The user password (can copy and print)
  owner: '5678', // The owner password (has all rights)
  accessFlags: <PdfAccessFlags>{
    PdfAccessFlags.Copy,
    PdfAccessFlags.Print,
  },
  level: PdfAESLevel.high,
);

pdf.addPage(
  Page(
    build: (Context context) {
      return Text('This text is encrypted using AES 256');
    },
  ),
);

final File file = File('encrypted.pdf');
await file.writeAsBytes(await pdf.save());
```

## Generate a signed document

```dart
final pdf = Document();

// Convert the PEM private key to BER
final privateKey = PdfSign.pemPrivateKey(
  File('key0.pem').readAsStringSync(),
);

// Convert the PEM x509 certificate to BER
final certificate = PdfSign.pemCertificate(
  File('cert0.pem').readAsStringSync(),
);

// If the chain is made of multiple certificates and a CA,
// put the sign certificate first.
final chain = [certificate];

pdf.addPage(
  Page(
    build: (Context context) => Column(
      children: <Widget>[
        Text('Click on this signature for more info:'),
        Signature(
          name: 'Signature',
          value: PdfSign.rsaSha1(
            privateKey: privateKey,
            certificates: chain,
          ),
          child: PdfLogo(),
        ),
      ],
    ),
  ),
);

final File file = File('signed.pdf');
await file.writeAsBytes(await pdf.save());
```

## Generate a self-signed certificate

Generate a 2048 bits RSA key pair using `OpenSSL`

```shell
openssl genpkey -outform PEM -algorithm rsa -pkeyopt rsa_keygen_bits:2048 -out key.pem
```

Generate a self-signed certificate using `OpenSSL` for tests

```shell
openssl req -new -x509 -days 365 -key key.pem -out cert.pem -subj "/CN=John Doe"
```

## Load an existing document for updating

It's also possible to include a signature to the existing document.

```dart
// Load the existing document from disk (can be from network or anything else)
final template = File('template.pdf').readAsBytesSync();

// Import the original document and draw something on the first page
final pdf = Document.load(
  PdfDocumentParser(template),
);

// Update the first page
pdf.editPage(
  0, // index 0 for the first page
  Page(
    build: (context) => Center(
      child: Text('Hello World!'),
    ),
  ),
);

// Save the document to a new file
final file = File('updated.pdf');
await file.writeAsBytes(await pdf.save());
```

## Merge multiple documents

```dart
final tools = PdfTools();

final parsed1 = PdfDocumentParser(await File('doc1.pdf').readAsBytes());
tools.addPages(parsed1);

final parsed2 = PdfDocumentParser(await File('doc2.pdf').readAsBytes());
tools.addPages(parsed2, [0, 2]); // only pages 0 and 2

final result = tools.save();

final file = File('merged.pdf');
await file.writeAsBytes(result);
```
