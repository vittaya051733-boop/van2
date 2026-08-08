import 'dart:convert';



import 'package:http/http.dart' as http;



class OmiseCardTokenHelper {

  const OmiseCardTokenHelper._();



  static Future<String> createToken({

    required String publicKey,

    required String cardNumber,

    required String cardName,

    required String expirationMonth,

    required String expirationYear,

    required String securityCode,

  }) async {

    final normalizedKey = publicKey.trim();

    if (!normalizedKey.startsWith('pkey_')) {

      throw Exception('ไม่พบ Omise public key');

    }



    return _createTokenWithPublicKey(

      publicKey: normalizedKey,

      cardNumber: cardNumber,

      cardName: cardName,

      expirationMonth: expirationMonth,

      expirationYear: expirationYear,

      securityCode: securityCode,

    );

  }



  static Future<String> _createTokenWithPublicKey({

    required String publicKey,

    required String cardNumber,

    required String cardName,

    required String expirationMonth,

    required String expirationYear,

    required String securityCode,

  }) async {

    final normalizedYear = expirationYear.length == 2

        ? '20$expirationYear'

        : expirationYear;

    final auth = base64Encode(utf8.encode('$publicKey:'));

    final formBody = <String, String>{

      'card[name]': cardName.isNotEmpty ? cardName : 'Van Customer',

      'card[number]': cardNumber,

      'card[expiration_month]': expirationMonth,

      'card[expiration_year]': normalizedYear,

      'card[security_code]': securityCode,

    };

    final response = await http

        .post(

          Uri.parse('https://vault.omise.co/tokens'),

          headers: <String, String>{

            'Authorization': 'Basic $auth',

            'Content-Type': 'application/x-www-form-urlencoded',

          },

          body: formBody.entries

              .map(

                (entry) =>

                    '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',

              )

              .join('&'),

        )

        .timeout(const Duration(seconds: 30));



    final payload = jsonDecode(response.body);

    if (response.statusCode >= 400) {

      final message = payload is Map

          ? payload['message']?.toString()

          : null;

      throw Exception(

        message?.trim().isNotEmpty == true

            ? message!.trim()

            : 'ไม่สามารถสร้าง card token ได้',

      );

    }



    if (payload is! Map) {

      throw Exception('ไม่สามารถสร้าง card token ได้');

    }

    final token = payload['id']?.toString().trim();

    if (token == null || token.isEmpty) {

      throw Exception('ไม่สามารถสร้าง card token ได้');

    }

    return token;

  }

}

