// lib/services/resale_service.dart
// ResaleService – manages all Firestore mutations for the resale flow.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ResaleService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── List an asset for resale ──────────────────────────────────────────────
  // Sets isListedForResale = true on the asset doc and records resalePrice.
  Future<void> listForResale({
    required String assetId,
    required num    price,
    String?         description,
  }) async {
    _requireAuth();
    await _db.collection('assets').doc(assetId).update({
      'isListedForResale' : true,
      'resalePrice'       : price,
      'resaleListedAt'    : FieldValue.serverTimestamp(),
      if (description != null && description.isNotEmpty)
        'resaleDescription' : description
      else
        'resaleDescription' : FieldValue.delete(),
    });
  }

  // ── Remove a resale listing ───────────────────────────────────────────────
  // Sets isListedForResale = false; clears the price, description and timestamp.
  Future<void> removeListing(String assetId) async {
    _requireAuth();
    await _db.collection('assets').doc(assetId).update({
      'isListedForResale' : false,
      'resalePrice'       : FieldValue.delete(),
      'resaleDescription' : FieldValue.delete(),
      'resaleListedAt'    : FieldValue.delete(),
    });
  }

  // ── Check whether the current user owns a given asset ────────────────────
  Future<bool> isOwnedByCurrentUser(String assetId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final snap = await _db.collection('assets').doc(assetId).get();
    if (!snap.exists) return false;
    final d = snap.data()!;
    return (d['ownerId'] == uid) || (d['ownerUid'] == uid);
  }

  // ── Stream transfer history for an asset ─────────────────────────────────
  Stream<QuerySnapshot> getTransferHistory(String assetId) {
    return _db
        .collection('transfers')
        .where('assetId', isEqualTo: assetId)
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // ── Mark a completed transfer as a 'resale' type ─────────────────────────
  Future<void> markTransferAsResale(String transferDocId, String pricePaid) async {
    await _db.collection('transfers').doc(transferDocId).update({
      'transferType' : 'resale',
      'pricePaid'    : pricePaid,
    });
  }
  Future<void> clearListingAfterSale(String assetId) async {
    await _db.collection('assets').doc(assetId).update({
      'isListedForResale' : false,
      'resalePrice'       : FieldValue.delete(),
      'resaleDescription' : FieldValue.delete(),
      'resaleListedAt'    : FieldValue.delete(),
    });
  }

  void _requireAuth() {
    if (_auth.currentUser == null) {
      throw StateError('User must be signed in to perform resale operations.');
    }
  }
}