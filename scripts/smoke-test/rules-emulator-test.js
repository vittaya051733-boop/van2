/**
 * Comprehensive Firestore rules smoke test (emulator).
 * Covers van1 shop, van2 customer, van3 rider, van4 admin critical paths.
 */
const { readFileSync, existsSync } = require('fs');
const { join } = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, getDoc, serverTimestamp } = require('firebase/firestore');

async function mustFail(promise, label) {
  try {
    await assertFails(promise);
  } catch (error) {
    throw new Error(`${label}: ${error.message || error}`);
  }
}

const RULES_PATH = join(__dirname, '..', '..', 'firestore.rules');

const UID = {
  rider: 'smoke-rider-uid',
  customer: 'smoke-customer-uid',
  shop: 'smoke-shop-uid',
  otherShop: 'smoke-other-shop-uid',
  admin: 'smoke-admin-uid',
};

const ORDER = {
  assigned: 'smoke-order-assigned',
  shopActive: 'smoke-order-shop-active',
  delivered: 'smoke-order-delivered',
  deliveredLegacy: 'smoke-order-delivered-legacy',
  promptpay: 'smoke-order-promptpay',
  promptpayShopBlocked: 'smoke-order-promptpay-shop',
};

async function seed(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const now = new Date();

    await db.collection('riders').doc(UID.rider).set({
      onlineReady: true,
      passengerReady: false,
      fcmToken: 'smoke-token',
      displayName: 'Smoke Rider',
    });

    await db.collection('credits').doc(UID.rider).set({
      uid: UID.rider,
      balance: 1500,
      updatedAt: now,
    });
    await db.collection('credits').doc(UID.shop).set({
      uid: UID.shop,
      balance: 800,
      updatedAt: now,
    });

    await db.collection('customer_users').doc(UID.customer).set({
      displayName: 'Smoke Customer',
    });
    await db.collection('customer_users').doc(UID.shop).set({
      displayName: 'Smoke Shop',
    });

    await db.collection('shop_operations').doc(UID.shop).set({
      notifyNewOrders: true,
      pauseNewOrders: false,
    });

    await db.collection('products').doc('smoke-product-1').set({
      ownerUid: UID.shop,
      shopId: UID.shop,
      shopOwnerId: UID.shop,
      name: 'Smoke Product',
      isActive: true,
      price: 99,
    });

    await db.collection('public_shops').doc(UID.shop).set({
      shopName: 'Smoke Shop Public',
      isActive: true,
    });

    await db.collection('shop_registrations').doc(UID.shop).set({
      ownerId: UID.shop,
      shopName: 'Smoke Shop Private',
      email: 'smoke-shop@example.com',
      phone: '0800000001',
      isActive: true,
    });

    await db.collection('payment_config').doc('collection').set({
      recipientDisplayName: 'Smoke Payee',
      bankName: 'Smoke Bank',
      bankAccountNumber: '1234567890',
    });

    const baseOrder = {
      customerId: UID.customer,
      shopId: UID.shop,
      shopOwnerId: UID.shop,
      shopName: 'Smoke Shop',
      status: 'accepted',
      sourceApp: 'van2_customer',
      paymentMethod: 'cod',
      customerConfirmed: true,
      riderNotifyReady: true,
      productIds: ['smoke-product-1'],
      createdAt: now,
    };

    await db.collection('orders').doc(ORDER.assigned).set({
      ...baseOrder,
      driverId: UID.rider,
      status: 'accepted',
    });

    await db.collection('orders').doc(ORDER.shopActive).set({
      ...baseOrder,
      status: 'preparing',
    });

    await db.collection('orders').doc(ORDER.delivered).set({
      ...baseOrder,
      driverId: UID.rider,
      status: 'delivered',
      deliveredAt: now,
    });

    await db.collection('orders').doc(ORDER.deliveredLegacy).set({
      customerId: UID.customer,
      shopId: UID.shop,
      shopName: 'Smoke Shop',
      status: 'delivered',
      sourceApp: 'van2_customer',
      paymentMethod: 'cod',
      customerConfirmed: true,
      riderNotifyReady: true,
      deliveryProofCapturedById: UID.rider,
      products: [
        {
          productId: 'smoke-product-1',
          name: 'Smoke Product',
          quantity: 1,
        },
      ],
      createdAt: now,
      deliveredAt: now,
    });

    await db.collection('orders').doc(ORDER.promptpay).set({
      ...baseOrder,
      shopId: UID.otherShop,
      shopOwnerId: UID.otherShop,
      driverId: UID.rider,
      status: 'pending',
      paymentMethod: 'promptpay_qr',
      paymentStatus: 'pending',
    });

    await db.collection('orders').doc(ORDER.promptpayShopBlocked).set({
      ...baseOrder,
      driverId: UID.rider,
      status: 'pending',
      paymentMethod: 'promptpay_qr',
      paymentStatus: 'pending',
    });

    await db.collection('product_reviews').doc(`${ORDER.delivered}_smoke-product-1`).set({
      orderId: ORDER.delivered,
      productId: 'smoke-product-1',
      shopId: UID.shop,
      shopOwnerId: UID.shop,
      customerId: UID.customer,
      rating: 5,
      comment: 'smoke product review',
      imageUrls: [],
      status: 'visible',
      createdAt: now,
      updatedAt: now,
    });

    await db.collection('shop_reviews').doc(`${ORDER.delivered}_${UID.shop}`).set({
      orderId: ORDER.delivered,
      shopId: UID.shop,
      shopOwnerId: UID.shop,
      customerId: UID.customer,
      rating: 5,
      comment: 'smoke shop review',
      status: 'visible',
      createdAt: now,
      updatedAt: now,
    });

    await db.collection('rider_reviews').doc(`${ORDER.delivered}_${UID.rider}`).set({
      orderId: ORDER.delivered,
      riderId: UID.rider,
      customerId: UID.customer,
      rating: 5,
      comment: 'smoke rider review',
      status: 'visible',
      createdAt: now,
      updatedAt: now,
    });

    await db.collection('admin_support_tickets').doc('smoke-ticket-open').set({
      sourceApp: 'van2',
      sourceLabel: 'ลูกค้า',
      requesterUid: UID.customer,
      requesterName: 'Smoke Customer',
      topicKey: 'order_issue',
      topicLabel: 'ปัญหาออเดอร์',
      message: 'seed ticket',
      imageUrls: [],
      status: 'open',
      createdAt: now,
      updatedAt: now,
    });

    await db.collection('chats').doc(`chat_${UID.customer}_${UID.shop}`).set({
      participants: [UID.customer, UID.shop],
      participantNames: {
        [UID.customer]: 'Smoke Customer',
        [UID.shop]: 'Smoke Shop',
      },
    });
    await db
      .collection('chats')
      .doc(`chat_${UID.customer}_${UID.shop}`)
      .collection('messages')
      .doc('seed-message')
      .set({
        senderId: UID.shop,
        receiverId: UID.customer,
        text: 'seed',
        createdAt: now,
      });

    await db.collection('app_notifications').doc('smoke-notification-van2').set({
      targetApp: 'van2',
      recipientUid: UID.customer,
      title: 'Smoke notification',
      body: 'Smoke body',
      orderId: ORDER.assigned,
      action: 'order_update',
      createdAt: now,
    });

    await db.collection('app_notifications').doc('smoke-notification-van1').set({
      targetApp: 'van1',
      recipientUid: UID.shop,
      title: 'Smoke shop notification',
      body: 'New order',
      orderId: ORDER.shopActive,
      action: 'order_accepted',
      createdAt: now,
    });

    await db.collection('admins').doc('smoke-admin@example.com').set({
      active: true,
      displayName: 'Smoke Registry Admin',
    });

    await db.collection('product_admin_reviews').doc('smoke-product-review-pending').set({
      ownerUid: UID.shop,
      shopName: 'Smoke Shop',
      name: 'Smoke Pending Review Product',
      price: 120,
      adminReviewStatus: 'pending',
      aiIsLegalInThailand: false,
      aiLegalAnalysisReason: 'smoke test illegal flag',
      reviewType: 'create',
      submittedByUid: UID.shop,
      submittedAt: now,
      updatedAt: now,
    });
  });
}

async function runVan3RiderTests(riderDb) {
  await assertSucceeds(
    riderDb.collection('orders').where('driverId', '==', UID.rider).get(),
    'van3: rider orders query (driverId == uid)',
  );
  await assertSucceeds(
    riderDb.collection('riders').doc(UID.rider).get(),
    'van3: rider profile read',
  );
  await assertSucceeds(
    riderDb.collection('riders').doc(UID.rider).update({ fcmToken: 'smoke-token-2' }),
    'van3: rider profile update (fcmToken)',
  );
  await assertSucceeds(
    riderDb.collection('credits').doc(UID.rider).get(),
    'van3: rider credits read',
  );
  await assertSucceeds(
    riderDb.collection('orders').doc(ORDER.assigned).get(),
    'van3: assigned order single read',
  );
  await assertSucceeds(
    riderDb.collection('rider_reviews').doc(`${ORDER.delivered}_${UID.rider}`).get(),
    'van3: rider review read',
  );
  await assertSucceeds(
    riderDb.collection('payment_config').doc('collection').get(),
    'van3: payment_config read',
  );
}

async function runVan1ShopTests(shopDb) {
  await assertSucceeds(
    shopDb.collection('orders').doc(ORDER.shopActive).get(),
    'van1: shop active order read',
  );
  await assertSucceeds(
    shopDb.collection('orders').doc(ORDER.delivered).get(),
    'van1: shop delivered order read',
  );
  await assertSucceeds(
    shopDb.collection('shop_operations').doc(UID.shop).get(),
    'van1: shop_operations read',
  );
  await assertSucceeds(
    shopDb
      .collection('app_notifications')
      .where('targetApp', '==', 'van1')
      .where('recipientUid', '==', UID.shop)
      .get(),
    'van1: shop notifications list',
  );
  await assertSucceeds(
    shopDb.collection('product_reviews').doc(`${ORDER.delivered}_smoke-product-1`).get(),
    'van1: merchant product review read',
  );
  await assertSucceeds(
    shopDb.collection('shop_reviews').doc(`${ORDER.delivered}_${UID.shop}`).get(),
    'van1: merchant shop review read',
  );
  await assertSucceeds(
    shopDb.collection('products').doc('smoke-product-1').get(),
    'van1: own product read',
  );
  await assertSucceeds(
    shopDb.collection('credits').doc(UID.shop).get(),
    'van1: shop credits read',
  );

  // PromptPay unverified — shop must NOT read (regression guard)
  await mustFail(
    shopDb.collection('orders').doc(ORDER.promptpayShopBlocked).get(),
    'van1: shop blocked on unverified promptpay order',
  );
  await assertSucceeds(
    setDoc(doc(shopDb, 'admin_support_tickets', 'smoke-ticket-shop'), {
      sourceApp: 'van1',
      sourceLabel: 'ร้านค้า',
      requesterUid: UID.shop,
      requesterName: 'Smoke Shop',
      topicKey: 'order_management',
      topicLabel: 'ปัญหาออเดอร์จากลูกค้า',
      message: 'smoke shop support',
      imageUrls: [],
      status: 'open',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
    'van1: shop creates admin_support_ticket',
  );
}

async function runVan2CustomerTests(customerDb) {
  await assertSucceeds(
    customerDb.collection('customer_users').doc(UID.customer).get(),
    'van2: customer profile read',
  );
  await assertSucceeds(
    customerDb.collection('orders').doc(ORDER.delivered).get(),
    'van2: customer delivered order read',
  );
  await assertSucceeds(
    customerDb.collection('products').doc('smoke-product-1').get(),
    'van2: active product read',
  );
  await assertSucceeds(
    customerDb.collection('public_shops').doc(UID.shop).get(),
    'van2: public shop read',
  );
  await assertSucceeds(
    customerDb.collection('riders').where('onlineReady', '==', true).limit(5).get(),
    'van2: online riders query (cart)',
  );
  await assertSucceeds(
    customerDb.collection('payment_config').doc('collection').get(),
    'van2: payment_config read',
  );
  await assertSucceeds(
    customerDb
      .collection('chats')
      .doc(`chat_${UID.customer}_${UID.shop}`)
      .collection('messages')
      .get(),
    'van2: customer chat messages read',
  );
  await assertSucceeds(
    customerDb
      .collection('app_notifications')
      .where('recipientUid', '==', UID.customer)
      .get(),
    'van2: customer notifications list',
  );
  await assertSucceeds(
    customerDb.collection('app_notifications').doc('smoke-notification-van2').update({
      isRead: true,
      read: true,
      readAt: new Date(),
    }),
    'van2: customer marks notification read',
  );
  await assertSucceeds(
    customerDb.collection('product_reviews').doc(`${ORDER.delivered}_smoke-product-1`).get(),
    'van2: visible product review read',
  );
  await assertSucceeds(
    setDoc(customerDb.collection('shop_reviews').doc(`${ORDER.deliveredLegacy}_${UID.shop}`), {
      orderId: ORDER.deliveredLegacy,
      shopId: UID.shop,
      shopOwnerId: UID.shop,
      customerId: UID.customer,
      rating: 5,
      comment: 'legacy shop review create',
      imageUrls: [],
      status: 'visible',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
    'van2: create shop review on legacy delivered order',
  );
  await assertSucceeds(
    setDoc(
      customerDb.collection('product_reviews').doc(`${ORDER.deliveredLegacy}_smoke-product-1`),
      {
        orderId: ORDER.deliveredLegacy,
        productId: 'smoke-product-1',
        shopId: UID.shop,
        shopOwnerId: UID.shop,
        customerId: UID.customer,
        rating: 4,
        comment: 'legacy product review create',
        imageUrls: [],
        status: 'visible',
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
    ),
    'van2: create product review without productIds[]',
  );
  await assertSucceeds(
    setDoc(customerDb.collection('rider_reviews').doc(`${ORDER.deliveredLegacy}_${UID.rider}`), {
      orderId: ORDER.deliveredLegacy,
      riderId: UID.rider,
      customerId: UID.customer,
      rating: 5,
      comment: 'legacy rider review via deliveryProofCapturedById',
      imageUrls: [],
      status: 'visible',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
    'van2: create rider review when driverId missing',
  );
  await assertSucceeds(
    customerDb.collection('admin_support_tickets').doc('smoke-ticket-open').get(),
    'van2: customer reads own support ticket',
  );
  await assertSucceeds(
    setDoc(
      doc(
        customerDb,
        'admin_support_tickets',
        'smoke-ticket-open',
        'messages',
        'smoke-customer-reply',
      ),
      {
        senderRole: 'requester',
        senderUid: UID.customer,
        senderName: 'Smoke Customer',
        message: 'ข้อความตอบกลับจากลูกค้า',
        imageUrls: [],
        createdAt: serverTimestamp(),
      },
    ),
    'van2: customer replies on support thread',
  );
  await assertSucceeds(
    updateDoc(doc(customerDb, 'admin_support_tickets', 'smoke-ticket-open'), {
      lastMessagePreview: 'ข้อความตอบกลับจากลูกค้า',
      lastMessageRole: 'requester',
      unreadForAdmin: true,
      updatedAt: serverTimestamp(),
      lastMessageAt: serverTimestamp(),
    }),
    'van2: customer updates ticket after reply',
  );
  await assertSucceeds(
    setDoc(doc(customerDb, 'admin_support_tickets', 'smoke-ticket-customer'), {
      sourceApp: 'van2',
      sourceLabel: 'ลูกค้า',
      requesterUid: UID.customer,
      requesterName: 'Smoke Customer',
      topicKey: 'order_issue',
      topicLabel: 'ปัญหาออเดอร์',
      message: 'smoke support message',
      imageUrls: [],
      status: 'open',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
    'van2: customer creates admin_support_ticket',
  );
}

async function runSecurityNegativeTests(customerDb, shopDb, riderDb) {
  await mustFail(
    customerDb.collection('orders').doc(ORDER.delivered).update({
      paymentStatus: 'verified',
    }),
    'van2: customer cannot escalate paymentStatus to verified',
  );
  await mustFail(
    customerDb.collection('orders').doc(ORDER.delivered).update({
      grandTotal: 1,
    }),
    'van2: customer cannot lower grandTotal',
  );
  await mustFail(
    setDoc(doc(customerDb, 'credits', 'smoke-fake-credit'), {
      uid: UID.customer,
      amount: 99999,
      type: 'fake_top_up',
      orderId: ORDER.delivered,
      timestamp: serverTimestamp(),
    }),
    'van2: customer cannot mint arbitrary credits',
  );
  await mustFail(
    customerDb.collection('shop_registrations').doc(UID.shop).get(),
    'van2: customer cannot read private shop registration',
  );
  await mustFail(
    customerDb.collection('admins').get(),
    'van2: customer cannot list admins directory',
  );
  await assertSucceeds(
    customerDb.collection('public_shops').doc(UID.shop).get(),
    'van2: customer can read public_shops profile',
  );
  await assertSucceeds(
    shopDb.collection('shop_registrations').doc(UID.shop).get(),
    'van1: shop owner can read own registration',
  );
  await assertSucceeds(
    updateDoc(doc(shopDb, 'orders', ORDER.shopActive), {
      status: 'preparing',
      shopDecisionStatus: 'accepted',
      updatedAt: serverTimestamp(),
    }),
    'van1: shop can update order workflow fields',
  );
  await assertSucceeds(
    setDoc(doc(riderDb, 'credits', `order_pay_at_destination_${ORDER.assigned}_${UID.rider}`), {
      uid: UID.rider,
      amount: -50,
      type: 'order_pay_at_destination_hold',
      orderId: ORDER.assigned,
      source: 'smoke_test',
      timestamp: serverTimestamp(),
    }),
    'van3: rider can create pay-at-destination hold ledger entry',
  );
  await mustFail(
    setDoc(doc(customerDb, 'checkout_quotes', 'smoke-quote'), {
      customerId: UID.customer,
      grandTotal: 100,
      createdAt: serverTimestamp(),
    }),
    'van2: client cannot write checkout_quotes (phase 2)',
  );
  await mustFail(
    setDoc(doc(customerDb, 'orders', 'smoke-client-cart-order'), {
      customerId: UID.customer,
      sourceApp: 'van2_customer',
      shopId: UID.shop,
      shopOwnerId: UID.shop,
      paymentStatus: 'cash_on_delivery',
      paymentMethod: 'cash_on_delivery',
      grandTotal: 150,
      subtotal: 120,
      shippingFee: 30,
      createdAt: serverTimestamp(),
    }),
    'van2 phase2: client cannot create cart order directly',
  );
  await mustFail(
    setDoc(doc(customerDb, 'orders', 'smoke-client-nationwide'), {
      customerId: UID.customer,
      sourceApp: 'van2_customer',
      orderType: 'nationwide_parcel',
      shopId: UID.shop,
      paymentStatus: 'verified',
      paymentMethod: 'promptpay_qr',
      grandTotal: 200,
      subtotal: 150,
      shippingFee: 50,
      paymentSlip: { storagePath: 'payment_slips/x/slip.jpg' },
      paymentVerification: { status: 'verified' },
      createdAt: serverTimestamp(),
    }),
    'van2 phase2: client cannot create nationwide_parcel order directly',
  );
  await assertSucceeds(
    setDoc(doc(customerDb, 'orders', 'smoke-client-travel'), {
      customerId: UID.customer,
      sourceApp: 'van2_customer',
      orderType: 'travel_passenger',
      shopId: UID.shop,
      paymentStatus: 'cash_on_delivery',
      paymentMethod: 'cash_on_delivery',
      grandTotal: 80,
      subtotal: 80,
      createdAt: serverTimestamp(),
    }),
    'van2 phase2: client can still create travel_passenger order',
  );
  await mustFail(
    setDoc(doc(customerDb, 'auth_rate_limits', 'smoke-ip'), {
      count: 1,
      updatedAt: serverTimestamp(),
    }),
    'phase3: client cannot write auth_rate_limits',
  );
}

async function runOrderLifecycleE2e(shopDb, riderDb, customerDb) {
  await assertSucceeds(
    updateDoc(doc(shopDb, 'orders', ORDER.shopActive), {
      status: 'ready',
      shopDecisionStatus: 'accepted',
      updatedAt: serverTimestamp(),
    }),
    'e2e: van1 shop marks order ready',
  );

  await assertSucceeds(
    updateDoc(doc(riderDb, 'orders', ORDER.assigned), {
      status: 'delivering',
      updatedAt: serverTimestamp(),
    }),
    'e2e: van3 rider starts delivery',
  );

  await assertSucceeds(
    updateDoc(doc(riderDb, 'orders', ORDER.assigned), {
      status: 'delivered',
      deliveredAt: serverTimestamp(),
      deliveryProofCapturedById: UID.rider,
      updatedAt: serverTimestamp(),
    }),
    'e2e: van3 rider completes delivery',
  );

  const deliveredSnap = await getDoc(doc(customerDb, 'orders', ORDER.assigned));
  if (!deliveredSnap.exists() || deliveredSnap.data().status !== 'delivered') {
    throw new Error('e2e: van2 customer cannot read delivered order');
  }
}

async function runVan4AdminTests(adminDb, customerDb) {
  await assertSucceeds(
    adminDb.collection('admin_support_tickets').orderBy('createdAt', 'desc').limit(20).get(),
    'van4: admin support inbox list',
  );
  await assertSucceeds(
    adminDb.collection('admin_support_tickets').doc('smoke-ticket-open').update({
      status: 'in_progress',
      updatedAt: new Date(),
    }),
    'van4: admin updates support ticket status',
  );
  await assertSucceeds(
    adminDb
      .collection('admin_support_tickets')
      .doc('smoke-ticket-open')
      .collection('messages')
      .doc('smoke-admin-reply')
      .set({
        senderRole: 'admin',
        senderUid: UID.admin,
        senderName: 'Admin',
        message: 'ตอบกลับจากแอดมิน (smoke)',
        imageUrls: [],
        createdAt: serverTimestamp(),
      }),
    'van4: admin creates support reply message',
  );
  await assertSucceeds(
    adminDb.collection('admin_support_tickets').doc('smoke-ticket-open').update({
      status: 'in_progress',
      lastMessagePreview: 'ตอบกลับจากแอดมิน (smoke)',
      lastMessageRole: 'admin',
      unreadForRequester: true,
      unreadForAdmin: false,
      updatedAt: serverTimestamp(),
      lastMessageAt: serverTimestamp(),
    }),
    'van4: admin marks ticket unread for requester',
  );
  await assertSucceeds(
    adminDb.collection('app_notifications').add({
      targetApp: 'van2',
      recipientUid: UID.customer,
      ticketId: 'smoke-ticket-open',
      title: 'แอดมินตอบกลับ',
      body: 'ตอบกลับจากแอดมิน (smoke)',
      action: 'admin_support_reply',
      sourceApp: 'van4_admin',
      read: false,
      createdAt: serverTimestamp(),
    }),
    'van4: admin creates support reply notification',
  );
  await assertSucceeds(
    adminDb.collection('platform_announcements').doc('smoke-announcement').set({
      title: 'Smoke announcement',
      body: 'Test announcement body',
      targetApps: ['van2'],
      recipientCount: 1,
      createdAt: serverTimestamp(),
      createdBy: UID.admin,
      sourceApp: 'van4_admin',
    }),
    'van4: admin creates platform announcement record',
  );
  await assertSucceeds(
    adminDb.collection('platform_announcements').orderBy('createdAt', 'desc').limit(10).get(),
    'van4: admin lists platform announcements',
  );
  await assertSucceeds(
    adminDb.collection('app_notifications').add({
      targetApp: 'van2',
      recipientUid: UID.customer,
      title: 'Smoke announcement',
      body: 'Test announcement body',
      action: 'admin_announcement',
      sourceApp: 'van4_admin',
      senderId: UID.admin,
      announcementId: 'smoke-announcement',
      read: false,
      isRead: false,
      createdAt: serverTimestamp(),
    }),
    'van4: admin fan-out announcement notification',
  );
  await assertSucceeds(
    setDoc(doc(adminDb, 'admin_support_knowledge', 'smoke-ticket-open'), {
      ticketId: 'smoke-ticket-open',
      sourceApp: 'van2',
      sourceLabel: 'ลูกค้า',
      topicKey: 'order_issue',
      topicLabel: 'ปัญหาออเดอร์',
      requesterUid: UID.customer,
      question: 'seed ticket',
      questionImageUrls: [],
      transcript: [
        { role: 'requester', message: 'seed ticket', imageUrls: [] },
        { role: 'admin', message: 'ตอบกลับจากแอดมิน (smoke)', imageUrls: [] },
      ],
      qaPairs: [
        {
          question: 'seed ticket',
          answer: 'ตอบกลับจากแอดมิน (smoke)',
          questionImageUrls: [],
          answerImageUrls: [],
        },
      ],
      messageCount: 2,
      status: 'closed',
      closedAt: serverTimestamp(),
      closedByAdminUid: UID.admin,
    }),
    'van4: admin archives closed support ticket to knowledge',
  );
  await assertSucceeds(
    updateDoc(doc(adminDb, 'admin_support_tickets', 'smoke-ticket-open'), {
      status: 'closed',
      contactClosed: true,
      closedAt: serverTimestamp(),
      closedByAdminUid: UID.admin,
      unreadForRequester: true,
      unreadForAdmin: false,
      updatedAt: serverTimestamp(),
    }),
    'van4: admin closes support ticket',
  );
  await mustFail(
    setDoc(
      doc(
        customerDb,
        'admin_support_tickets',
        'smoke-ticket-open',
        'messages',
        'after-close-reply',
      ),
      {
        senderRole: 'requester',
        senderUid: UID.customer,
        senderName: 'Smoke Customer',
        message: 'should be blocked after close',
        imageUrls: [],
        createdAt: serverTimestamp(),
      },
    ),
    'van2: customer cannot reply on closed support ticket',
  );
  await assertSucceeds(
    adminDb.collection('orders').limit(10).get(),
    'van4: admin orders list',
  );
  await assertSucceeds(
    adminDb.collection('riders').limit(10).get(),
    'van4: admin riders list',
  );
  await assertSucceeds(
    adminDb
      .collection('product_admin_reviews')
      .where('adminReviewStatus', '==', 'pending')
      .get(),
    'van4: admin lists pending product reviews (custom claim)',
  );
  await assertSucceeds(
    getDoc(doc(adminDb, 'product_admin_reviews', 'smoke-product-review-pending')),
    'van4: admin reads pending product review doc',
  );
  await assertSucceeds(
    setDoc(doc(adminDb, 'admin_internal_threads', 'team'), {
      type: 'team',
      title: 'ห้องทีมแอดมิน',
      lastMessageAt: serverTimestamp(),
    }),
    'van4: admin creates internal team thread',
  );
  await assertSucceeds(
    setDoc(doc(adminDb, 'admin_internal_threads', 'team', 'messages', 'smoke-team-msg'), {
      senderUid: UID.admin,
      senderName: 'Admin',
      message: 'smoke admin team chat',
      imageUrls: [],
      attachments: [],
      createdAt: serverTimestamp(),
    }),
    'van4: admin posts internal team message',
  );
  await assertSucceeds(
    setDoc(doc(adminDb, 'admin_presence', UID.admin), {
      uid: UID.admin,
      fcmToken: 'smoke-admin-fcm',
      lastSeenAt: serverTimestamp(),
    }),
    'van4: admin writes own presence doc',
  );
  await assertSucceeds(
    adminDb.collection('admins').get(),
    'van4: admin lists admins directory',
  );
}

async function runVan4RegistryAdminTests(testEnv, shopDb) {
  const registryAdminDb = testEnv
    .authenticatedContext('smoke-registry-admin-uid', {
      email: 'smoke-admin@example.com',
    })
    .firestore();

  await assertSucceeds(
    registryAdminDb
      .collection('product_admin_reviews')
      .where('adminReviewStatus', '==', 'pending')
      .get(),
    'van4: registry admin lists pending product reviews',
  );
  await assertSucceeds(
    setDoc(
      doc(registryAdminDb, 'admins', 'smoke-admin@example.com'),
      {
        authUid: 'smoke-registry-admin-uid',
        email: 'smoke-admin@example.com',
        displayName: 'Smoke Registry Admin',
        lastSeenAt: serverTimestamp(),
        active: true,
      },
      { merge: true },
    ),
    'van4: registry admin syncs own admins doc presence fields',
  );
  await mustFail(
    shopDb
      .collection('product_admin_reviews')
      .where('adminReviewStatus', '==', 'pending')
      .get(),
    'van1: shop cannot list all pending product reviews',
  );
  await assertSucceeds(
    shopDb.collection('product_admin_reviews').doc('smoke-product-review-pending').get(),
    'van1: shop reads own pending product review',
  );
}

async function run() {
  if (!existsSync(RULES_PATH)) {
    throw new Error(`Missing rules file: ${RULES_PATH}`);
  }

  const rules = readFileSync(RULES_PATH, 'utf8');
  const testEnv = await initializeTestEnvironment({
    projectId: 'van-smoke-rules-test',
    firestore: { rules },
  });

  try {
    await seed(testEnv);

    const riderDb = testEnv.authenticatedContext(UID.rider).firestore();
    const customerDb = testEnv.authenticatedContext(UID.customer).firestore();
    const shopDb = testEnv.authenticatedContext(UID.shop).firestore();
    const adminDb = testEnv.authenticatedContext(UID.admin, { admin: true }).firestore();

    await runVan3RiderTests(riderDb);
    await runVan1ShopTests(shopDb);
    await runVan2CustomerTests(customerDb);
    await runSecurityNegativeTests(customerDb, shopDb, riderDb);
    await runVan4AdminTests(adminDb, customerDb);
    await runVan4RegistryAdminTests(testEnv, shopDb);
    await runOrderLifecycleE2e(shopDb, riderDb, customerDb);
    await assertSucceeds(
      updateDoc(doc(customerDb, 'admin_support_tickets', 'smoke-ticket-open'), {
        unreadForRequester: false,
        updatedAt: serverTimestamp(),
      }),
      'van2: customer marks support ticket read',
    );

    console.log('PASS rules-emulator: van3 rider + van1 shop + van2 customer + van4 admin + order lifecycle e2e');
  } finally {
    await testEnv.cleanup();
  }
}

run().catch((error) => {
  console.error('FAIL rules-emulator:', error.message || error);
  process.exit(1);
});
