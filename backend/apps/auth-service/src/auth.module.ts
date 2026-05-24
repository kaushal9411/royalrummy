import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { OtpService } from './otp.service';
import { DeviceService } from './device.service';
import { JwtStrategy } from './strategies/jwt.strategy';
import { User } from '../../libs/database/src/entities/user.entity';
import { RefreshToken } from '../../libs/database/src/entities/refresh-token.entity';
import { UserDevice } from '../../libs/database/src/entities/user-device.entity';
import { RedisModule } from '../../libs/redis/src/redis.module';

@Module({
  imports: [
    PassportModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get('JWT_SECRET'),
        signOptions: { expiresIn: '15m' },
      }),
    }),
    TypeOrmModule.forFeature([User, RefreshToken, UserDevice]),
    RedisModule,
  ],
  controllers: [AuthController],
  providers: [AuthService, OtpService, DeviceService, JwtStrategy],
  exports: [AuthService, JwtModule],
})
export class AuthModule {}
