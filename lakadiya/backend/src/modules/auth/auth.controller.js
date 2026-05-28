const { validationResult } = require('express-validator');
const authService = require('./auth.service');

const handleValidation = (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(400).json({ message: 'Validation failed', errors: errors.array() });
    return false;
  }
  return true;
};

const requestOtp = async (req, res, next) => {
  if (!handleValidation(req, res)) return;
  try {
    const data = await authService.requestOtp(req.body);
    res.json(data);
  } catch (err) { next(err); }
};

const verifyAndLogin = async (req, res, next) => {
  if (!handleValidation(req, res)) return;
  try {
    const data = await authService.verifyAndLogin(req.body);
    res.json(data);
  } catch (err) { next(err); }
};

const guestLogin = async (req, res, next) => {
  if (!handleValidation(req, res)) return;
  try {
    const data = await authService.guestLogin(req.body);
    res.json(data);
  } catch (err) { next(err); }
};

const googleAuth = async (req, res, next) => {
  try {
    const data = await authService.googleAuth(req.body);
    res.json(data);
  } catch (err) { next(err); }
};

const adminLogin = async (req, res, next) => {
  if (!handleValidation(req, res)) return;
  try {
    const data = await authService.adminLogin(req.body);
    res.json(data);
  } catch (err) { next(err); }
};

module.exports = { requestOtp, verifyAndLogin, guestLogin, googleAuth, adminLogin };
