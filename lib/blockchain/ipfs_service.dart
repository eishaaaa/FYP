// lib/services/ipfs_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

class IPFSService {
  // Pinata credentials (free tier: 1GB storage)
  static const String _pinataApiKey = 'YOUR_PINATA_API_KEY';
  static const String _pinataSecretKey = 'YOUR_PINATA_SECRET_KEY';

  // Pinata endpoints
  static const String _pinataUploadUrl = 'https://api.pinata.cloud/pinning/pinFileToIPFS';
  static const String _pinataJsonUrl = 'https://api.pinata.cloud/pinning/pinJSONToIPFS';
  static const String _pinataGateway = 'https://gateway.pinata.cloud/ipfs/';

  // Alternative: Public IPFS gateway (slower but free)
  static const String _publicGateway = 'https://ipfs.io/ipfs/';

  /// Upload file to IPFS via Pinata
  Future<IPFSUploadResult> uploadFile({
    required Uint8List fileBytes,
    required String fileName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_pinataUploadUrl),
      );

      // Add headers
      request.headers.addAll({
        'pinata_api_key': _pinataApiKey,
        'pinata_secret_api_key': _pinataSecretKey,
      });

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

      // Add metadata if provided
      if (metadata != null) {
        request.fields['pinataMetadata'] = jsonEncode({
          'name': fileName,
          'keyvalues': metadata,
        });
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(responseBody);
        final ipfsHash = jsonResponse['IpfsHash'] as String;

        print('✅ File uploaded to IPFS: $ipfsHash');

        return IPFSUploadResult(
          success: true,
          ipfsHash: ipfsHash,
          ipfsUrl: '$_pinataGateway$ipfsHash',
          size: fileBytes.length,
          sha256Hash: _calculateSHA256(fileBytes),
        );
      } else {
        print('❌ IPFS upload failed: ${response.statusCode}');
        return IPFSUploadResult(
          success: false,
          error: 'Upload failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error uploading to IPFS: $e');
      return IPFSUploadResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Upload JSON metadata to IPFS
  Future<IPFSUploadResult> uploadJSON({
    required Map<String, dynamic> jsonData,
    String? name,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_pinataJsonUrl),
        headers: {
          'Content-Type': 'application/json',
          'pinata_api_key': _pinataApiKey,
          'pinata_secret_api_key': _pinataSecretKey,
        },
        body: jsonEncode({
          'pinataContent': jsonData,
          'pinataMetadata': {
            'name': name ?? 'metadata',
          },
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final ipfsHash = jsonResponse['IpfsHash'] as String;

        print('✅ JSON uploaded to IPFS: $ipfsHash');

        final jsonBytes = utf8.encode(jsonEncode(jsonData));

        return IPFSUploadResult(
          success: true,
          ipfsHash: ipfsHash,
          ipfsUrl: '$_pinataGateway$ipfsHash',
          size: jsonBytes.length,
          sha256Hash: _calculateSHA256(Uint8List.fromList(jsonBytes)),
        );
      } else {
        print('❌ JSON upload failed: ${response.statusCode}');
        return IPFSUploadResult(
          success: false,
          error: 'Upload failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error uploading JSON to IPFS: $e');
      return IPFSUploadResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Retrieve file from IPFS
  Future<Uint8List?> retrieveFile(String ipfsHash) async {
    try {
      // Try Pinata gateway first (faster)
      final pinataUrl = '$_pinataGateway$ipfsHash';
      var response = await http.get(Uri.parse(pinataUrl));

      // Fallback to public gateway if Pinata fails
      if (response.statusCode != 200) {
        final publicUrl = '$_publicGateway$ipfsHash';
        response = await http.get(Uri.parse(publicUrl));
      }

      if (response.statusCode == 200) {
        print('✅ File retrieved from IPFS: $ipfsHash');
        return response.bodyBytes;
      } else {
        print('❌ Failed to retrieve file: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error retrieving from IPFS: $e');
      return null;
    }
  }

  /// Retrieve JSON from IPFS
  Future<Map<String, dynamic>?> retrieveJSON(String ipfsHash) async {
    try {
      final bytes = await retrieveFile(ipfsHash);
      if (bytes != null) {
        final jsonString = utf8.decode(bytes);
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('❌ Error parsing JSON from IPFS: $e');
      return null;
    }
  }

  /// Verify file integrity using SHA-256 hash
  Future<bool> verifyFileIntegrity({
    required String ipfsHash,
    required String expectedSHA256,
  }) async {
    try {
      final bytes = await retrieveFile(ipfsHash);
      if (bytes == null) return false;

      final actualHash = _calculateSHA256(bytes);
      final isValid = actualHash.toLowerCase() == expectedSHA256.toLowerCase();

      if (isValid) {
        print('✅ File integrity verified');
      } else {
        print('❌ File integrity check failed');
        print('   Expected: $expectedSHA256');
        print('   Actual: $actualHash');
      }

      return isValid;
    } catch (e) {
      print('❌ Error verifying file integrity: $e');
      return false;
    }
  }

  /// Create NFT metadata for electronics
  Map<String, dynamic> createElectronicsMetadata({
    required String brand,
    required String model,
    required String serialNumber,
    required String warrantyExpiry,
    required String condition,
    String? warrantyDocHash,
    String? imageHash,
  }) {
    return {
      'name': '$brand $model',
      'description': 'Blockchain-authenticated $brand $model with serial $serialNumber',
      'image': imageHash != null ? 'ipfs://$imageHash' : '',
      'attributes': [
        {'trait_type': 'Brand', 'value': brand},
        {'trait_type': 'Model', 'value': model},
        {'trait_type': 'Serial Number', 'value': serialNumber},
        {'trait_type': 'Warranty Expiry', 'value': warrantyExpiry},
        {'trait_type': 'Condition', 'value': condition},
      ],
      'properties': {
        'warranty_certificate': warrantyDocHash != null ? 'ipfs://$warrantyDocHash' : null,
        'minted_date': DateTime.now().toIso8601String(),
        'authenticity': 'Verified by Digital Goods',
      },
    };
  }

  /// Create NFT metadata for land
  Map<String, dynamic> createLandMetadata({
    required String location,
    required String city,
    required int totalArea,
    required String areaUnit,
    required int totalFractions,
    required String pricePerFraction,
    String? deedHash,
    String? imageHash,
  }) {
    return {
      'name': '$location - $totalArea $areaUnit',
      'description': 'Fractionalized land property in $city. Total area: $totalArea $areaUnit',
      'image': imageHash != null ? 'ipfs://$imageHash' : '',
      'attributes': [
        {'trait_type': 'Location', 'value': location},
        {'trait_type': 'City', 'value': city},
        {'trait_type': 'Total Area', 'value': totalArea},
        {'trait_type': 'Area Unit', 'value': areaUnit},
        {'trait_type': 'Total Fractions', 'value': totalFractions},
        {'trait_type': 'Price Per Fraction', 'value': '$pricePerFraction MATIC'},
      ],
      'properties': {
        'property_deed': deedHash != null ? 'ipfs://$deedHash' : null,
        'registration_date': DateTime.now().toIso8601String(),
        'verification_status': 'Pending',
      },
    };
  }

  /// Calculate SHA-256 hash of bytes
  String _calculateSHA256(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Get IPFS URL from hash
  String getIPFSUrl(String hash) {
    return '$_pinataGateway$hash';
  }

  /// Extract hash from IPFS URL
  String? extractHashFromUrl(String url) {
    if (url.startsWith('ipfs://')) {
      return url.replaceFirst('ipfs://', '');
    } else if (url.contains('/ipfs/')) {
      return url.split('/ipfs/').last;
    }
    return null;
  }
}

/// Result class for IPFS uploads
class IPFSUploadResult {
  final bool success;
  final String? ipfsHash;
  final String? ipfsUrl;
  final int? size;
  final String? sha256Hash;
  final String? error;

  IPFSUploadResult({
    required this.success,
    this.ipfsHash,
    this.ipfsUrl,
    this.size,
    this.sha256Hash,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'ipfsHash': ipfsHash,
      'ipfsUrl': ipfsUrl,
      'size': size,
      'sha256Hash': sha256Hash,
      'error': error,
    };
  }

  @override
  String toString() {
    if (success) {
      return 'IPFS Upload Success: $ipfsHash (${_formatSize(size ?? 0)})';
    } else {
      return 'IPFS Upload Failed: $error';
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}