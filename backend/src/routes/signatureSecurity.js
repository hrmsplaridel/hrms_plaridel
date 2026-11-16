'use strict';
const express=require('express');
const {rateLimit}=require('express-rate-limit');
const {pool}=require('../config/db');
const {authMiddleware}=require('../middleware/auth');
const {authorizeSigning}=require('../services/signatureAuthorization');
const router=express.Router();
const limit=rateLimit({windowMs:15*60*1000,limit:5,standardHeaders:'draft-8',legacyHeaders:false,
  keyGenerator:req=>String(req.user.id),skipSuccessfulRequests:true,
  message:{error:'Too many signing confirmation attempts. Please try again later.'}});
router.post('/authorize',authMiddleware,limit,async(req,res)=>{
 try{
  const authorization=await authorizeSigning(pool,req.user,req.body);
  res.setHeader('Cache-Control','no-store');
  res.json({authorization});
 }catch(error){res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Could not confirm signing.'});}
});
module.exports=router;
