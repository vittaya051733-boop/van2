const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const {
  VAN4_DATABASE_ID,
  VAN4_STORAGE_BUCKET,
} = require('./constants');

let _dbVan4;
let _storageVan4;

function getVan4Firestore() {
  if (!_dbVan4) {
    _dbVan4 = getFirestore(admin.app(), VAN4_DATABASE_ID);
  }
  return _dbVan4;
}

function getVan4StorageBucket() {
  if (!_storageVan4) {
    _storageVan4 = admin.storage().bucket(VAN4_STORAGE_BUCKET);
  }
  return _storageVan4;
}

module.exports = {
  getVan4Firestore,
  getVan4StorageBucket,
};
