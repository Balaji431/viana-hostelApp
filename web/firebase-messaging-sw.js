importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyCQ8IbpJj-KpPCLBa6x_HWbXKtrfQVGzC8",
  projectId: "hostel-app-3afa1",
  messagingSenderId: "907286443175",
  appId: "1:907286443175:web:8e3d09eda4a93",
  storageBucket: "hostel-app-3afa1.appspot.com"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  
  const notificationTitle = payload.data.title || payload.notification.title || 'Incoming Call';
  const notificationOptions = {
    body: payload.data.body || payload.notification.body || 'You have an incoming call from Warden',
    icon: '/favicon.png',
    data: payload.data
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.openWindow('/')
  );
});
