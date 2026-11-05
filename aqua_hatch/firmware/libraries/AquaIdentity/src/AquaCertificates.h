#pragma once
#include <string>
#include <cstddef>

namespace aqua_cert {
using Random = int (*)(void *, unsigned char *, size_t);
bool generateKey(Random random, void *context, std::string &pem);
bool issue(const std::string &subjectKey, const std::string &issuerKey,
           const std::string &subject, const std::string &issuer,
           const std::string &hostname, bool authority,
           const char *notBefore, const char *notAfter,
           Random random, void *context, std::string &certificate);
bool publicDer(const std::string &pem, std::string &der);
bool matchingKey(const std::string &certificate, const std::string &key,
                 Random random, void *context);
}
