const nodemailer = require('nodemailer');

let _transporter = null;

function getTransporter() {
  if (_transporter) return _transporter;
  _transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: process.env.GMAIL_USER,
      pass: process.env.GMAIL_APP_PASSWORD, // Gmail App Password (not account password)
    },
  });
  return _transporter;
}

async function sendEmail({ to, subject, html }) {
  if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
    console.warn('[Email] GMAIL_USER or GMAIL_APP_PASSWORD not set — skipping email');
    return;
  }
  await getTransporter().sendMail({
    from: `"Lakadiya" <${process.env.GMAIL_USER}>`,
    to,
    subject,
    html,
  });
}

// ── Templates ──────────────────────────────────────────────────────────────────

async function sendWithdrawalRequestEmail({ to, username, amount, txnId, requestedAt }) {
  await sendEmail({
    to,
    subject: 'Withdrawal Request Received — Lakadiya',
    html: `
      <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;background:#060C1A;color:#fff;border-radius:12px;overflow:hidden">
        <div style="background:linear-gradient(135deg,#0066FF,#003399);padding:28px 24px;text-align:center">
          <h1 style="margin:0;font-size:22px;letter-spacing:1px">♠ LAKADIYA</h1>
          <p style="margin:6px 0 0;opacity:.8;font-size:13px">Withdrawal Request</p>
        </div>
        <div style="padding:28px 24px">
          <p style="font-size:16px">Hi <strong>${username}</strong>,</p>
          <p>We have received your withdrawal request. Here are the details:</p>
          <table style="width:100%;border-collapse:collapse;margin:20px 0">
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Amount</td>
              <td style="padding:10px 0;font-weight:bold;font-size:18px;color:#00B0FF">₹${amount}</td>
            </tr>
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Transaction ID</td>
              <td style="padding:10px 0;font-size:13px;color:#ccc">${txnId}</td>
            </tr>
            <tr>
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Requested At</td>
              <td style="padding:10px 0;font-size:13px;color:#ccc">${requestedAt}</td>
            </tr>
          </table>
          <div style="background:#0E1A2E;border:1px solid #1E3050;border-radius:10px;padding:16px;margin-top:16px">
            <p style="margin:0;font-size:13px;color:#8899BB">Your withdrawal request is under review. Processing typically takes <strong style="color:#fff">24–48 hours</strong>. You will receive another email once it is processed.</p>
          </div>
        </div>
        <div style="padding:16px 24px;text-align:center;border-top:1px solid #1E3050">
          <p style="margin:0;font-size:11px;color:#556677">© ${new Date().getFullYear()} Lakadiya. This is a system-generated email. Please do not reply.</p>
        </div>
      </div>
    `,
  });
}

async function sendWithdrawalStatusEmail({ to, username, amount, txnId, status, remark }) {
  const isSuccess = status === 'success';
  const statusColor = isSuccess ? '#00E676' : '#FF4444';
  const statusLabel = isSuccess ? 'Approved & Processed' : 'Rejected';
  await sendEmail({
    to,
    subject: `Withdrawal ${isSuccess ? 'Processed' : 'Rejected'} — Lakadiya`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;background:#060C1A;color:#fff;border-radius:12px;overflow:hidden">
        <div style="background:linear-gradient(135deg,#0066FF,#003399);padding:28px 24px;text-align:center">
          <h1 style="margin:0;font-size:22px;letter-spacing:1px">♠ LAKADIYA</h1>
        </div>
        <div style="padding:28px 24px">
          <p style="font-size:16px">Hi <strong>${username}</strong>,</p>
          <p>Your withdrawal request has been updated:</p>
          <div style="text-align:center;padding:20px 0">
            <span style="background:${statusColor}22;border:1px solid ${statusColor};color:${statusColor};padding:8px 20px;border-radius:20px;font-weight:bold;font-size:15px">${statusLabel}</span>
          </div>
          <table style="width:100%;border-collapse:collapse;margin:20px 0">
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Amount</td>
              <td style="padding:10px 0;font-weight:bold;font-size:18px;color:#00B0FF">₹${amount}</td>
            </tr>
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Transaction ID</td>
              <td style="padding:10px 0;font-size:13px;color:#ccc">${txnId}</td>
            </tr>
            ${remark ? `<tr><td style="padding:10px 0;color:#8899BB;font-size:14px">Remark</td><td style="padding:10px 0;font-size:13px;color:#ccc">${remark}</td></tr>` : ''}
          </table>
        </div>
        <div style="padding:16px 24px;text-align:center;border-top:1px solid #1E3050">
          <p style="margin:0;font-size:11px;color:#556677">© ${new Date().getFullYear()} Lakadiya.</p>
        </div>
      </div>
    `,
  });
}

async function sendPaymentReceiptEmail({ to, username, amount, coins, txnId, paymentId, paidAt }) {
  await sendEmail({
    to,
    subject: 'Payment Successful — Lakadiya',
    html: `
      <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;background:#060C1A;color:#fff;border-radius:12px;overflow:hidden">
        <div style="background:linear-gradient(135deg,#00C853,#007E33);padding:28px 24px;text-align:center">
          <h1 style="margin:0;font-size:22px;letter-spacing:1px">♠ LAKADIYA</h1>
          <p style="margin:6px 0 0;opacity:.8;font-size:13px">Payment Receipt</p>
        </div>
        <div style="padding:28px 24px">
          <p style="font-size:16px">Hi <strong>${username}</strong>,</p>
          <p>Your payment was successful! Here is your receipt:</p>
          <table style="width:100%;border-collapse:collapse;margin:20px 0">
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Amount Paid</td>
              <td style="padding:10px 0;font-weight:bold;font-size:18px;color:#00E676">₹${amount}</td>
            </tr>
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Coins Added</td>
              <td style="padding:10px 0;font-weight:bold;color:#FFD700">🪙 ${coins} coins</td>
            </tr>
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Transaction ID</td>
              <td style="padding:10px 0;font-size:13px;color:#ccc">${txnId}</td>
            </tr>
            <tr style="border-bottom:1px solid #1E3050">
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Payment ID</td>
              <td style="padding:10px 0;font-size:13px;color:#ccc">${paymentId}</td>
            </tr>
            <tr>
              <td style="padding:10px 0;color:#8899BB;font-size:14px">Date & Time</td>
              <td style="padding:10px 0;font-size:13px;color:#ccc">${paidAt}</td>
            </tr>
          </table>
          <div style="background:#0E2818;border:1px solid #1E4030;border-radius:10px;padding:16px;margin-top:16px">
            <p style="margin:0;font-size:13px;color:#88BB99">Powered by Razorpay. This payment was processed securely. Keep this receipt for your records.</p>
          </div>
        </div>
        <div style="padding:16px 24px;text-align:center;border-top:1px solid #1E3050">
          <p style="margin:0;font-size:11px;color:#556677">© ${new Date().getFullYear()} Lakadiya. This is a system-generated receipt.</p>
        </div>
      </div>
    `,
  });
}

module.exports = { sendWithdrawalRequestEmail, sendWithdrawalStatusEmail, sendPaymentReceiptEmail };
