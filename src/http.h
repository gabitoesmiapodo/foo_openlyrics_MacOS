#pragma once
#include <string>
#include <vector>

namespace foobar2000_io
{
    class abort_callback;
}

namespace http
{
    struct Header
    {
        std::string name;
        std::string value;
    };

    struct Result
    {
        bool completed_successfully;
        long response_status;
        std::string response_content;
        std::string error_message;

        bool is_success() const;
    };

    Result get_http2(const std::string& url, foobar2000_io::abort_callback& abort);
    Result get_request(const std::string& url,
                       const std::vector<Header>& headers,
                       foobar2000_io::abort_callback& abort);
    // body may be empty for a bodyless POST (e.g. NetEase, LRCLIB challenge).
    // content_type is added as Content-Type header when non-empty.
    Result post_request(const std::string& url,
                        const std::vector<Header>& headers,
                        const std::string& body,
                        const std::string& content_type,
                        foobar2000_io::abort_callback& abort);
}
