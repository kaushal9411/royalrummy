const router = require('express').Router();
const { body } = require('express-validator');
const controller = require('./auth.controller');

router.post('/register', [
  body('username').isLength({ min: 3, max: 30 }).trim().escape(),
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 6 }),
], controller.register);

router.post('/login', [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
], controller.login);

router.post('/guest', controller.guestLogin);

router.post('/google', [
  body('googleId').notEmpty(),
  body('email').isEmail(),
  body('name').notEmpty(),
], controller.googleAuth);

router.post('/admin/login', [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
], controller.adminLogin);

module.exports = router;
