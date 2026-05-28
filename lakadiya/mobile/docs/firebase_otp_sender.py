"""
Firebase Cloud Messaging - Send OTP Notification
Backend helper to send OTP via FCM to a specific device

Usage:
    from firebase_admin import credentials, initialize_app, messaging
    cred = credentials.Certificate('path/to/firebase-adminsdk-key.json')
    initialize_app(cred)
    
    send_otp_notification('device-token-here', '123456')
"""

from firebase_admin import credentials, initialize_app, messaging
from datetime import datetime


def send_otp_notification(device_token: str, otp: str) -> dict:
    """
    Send OTP notification via Firebase Cloud Messaging
    
    Args:
        device_token: The FCM device token of the target device
        otp: The 6-digit OTP code
        
    Returns:
        dict with success status and message ID
    """
    
    message = messaging.MulticastMessage(
        notification=messaging.Notification(
            title='Your OTP Code',
            body=f'Your verification code is: {otp}',
        ),
        data={
            'type': 'OTP',
            'otp': otp,
            'timestamp': datetime.utcnow().isoformat(),
        },
        android=messaging.AndroidConfig(
            ttl=3600,  # 1 hour
            priority='high',
            notification=messaging.AndroidNotification(
                title='Your OTP Code',
                body=f'Your verification code is: {otp}',
                icon='ic_launcher',
                color='#4CAF50',
                sound='default',
                channel_id='otp_channel',
                click_action='FLUTTER_NOTIFICATION_CLICK',
            ),
        ),
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(
                        title='Your OTP Code',
                        body=f'Your verification code is: {otp}',
                    ),
                    sound='default',
                    badge=1,
                ),
            ),
        ),
        tokens=[device_token],
    )
    
    try:
        response = messaging.send_multicast(message)
        print(f'OTP notification sent. Success count: {response.success_count}')
        return {
            'success': True,
            'success_count': response.success_count,
            'failure_count': response.failure_count,
        }
    except Exception as e:
        print(f'Error sending OTP notification: {e}')
        raise


if __name__ == '__main__':
    # Initialize Firebase Admin SDK
    cred = credentials.Certificate('lakadiya-3e18a-firebase-adminsdk-fbsvc-0fe9480f2e.json')
    initialize_app(cred)
    
    # Example: Send OTP
    device_token = 'your-device-token-here'
    otp = '123456'
    
    result = send_otp_notification(device_token, otp)
    print('Result:', result)
