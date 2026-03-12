#include "stdafx.h"

#define CURL_STATICLIB
#include "curl/curl.h"
#include "curl/multi.h"
#include "http.h"
#include "logging.h"
#include "openlyrics_version.h" // Defines OPENLYRICS_VERSION

static void on_init()
{
    CURLcode result = curl_global_init(CURL_GLOBAL_DEFAULT);
    if(result != 0)
    {
        LOG_WARN("Failed to initial global libcurl state: %s", curl_easy_strerror(result));
    }
}

static void on_quit()
{
    curl_global_cleanup();
}

FB2K_ON_INIT_STAGE(on_init, init_stages::before_library_init);
FB2K_RUN_ON_QUIT(on_quit);

bool http::Result::is_success() const
{
    return completed_successfully && (response_status < 300);
}

static size_t write_callback(void* contents, size_t size, size_t nmemb, std::string* userp)
{
    size_t content_len = size * nmemb;
    userp->append(static_cast<char*>(contents), content_len);
    return content_len;
}

// Runs a pre-configured CURL easy handle on a CURLM multi handle.
// Consumes both handles (cleans them up). Also frees header_list if non-null.
static http::Result curl_perform(CURL* curl, CURLM* multi, curl_slist* header_list,
                                  char* error_buf, abort_callback& abort)
{
    http::Result result = {};
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &result.response_content);

    if(header_list)
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);

    const CURLMcode add_result = curl_multi_add_handle(multi, curl);
    if(add_result != CURLM_OK)
    {
        curl_slist_free_all(header_list);
        curl_easy_cleanup(curl);
        curl_multi_cleanup(multi);
        result.error_message = curl_multi_strerror(add_result);
        return result;
    }

    int num_running_handles = 1;
    while((num_running_handles > 0) && !abort.is_aborting())
    {
        const CURLMcode perform_result = curl_multi_perform(multi, &num_running_handles);
        if(perform_result != CURLM_OK)
        {
            LOG_WARN("Failed to perform request activity on curl multi handle: %s. Aborting request.",
                     curl_multi_strerror(perform_result));
            break;
        }

        const CURLMcode wait_result = curl_multi_wait(multi, nullptr, 0, 2, nullptr);
        if(wait_result != CURLM_OK)
        {
            LOG_WARN("Failed to wait for activity on curl multi handle: %s. Aborting request.",
                     curl_multi_strerror(wait_result));
            break;
        }
    }

    int msgs_remaining = 0;
    const CURLMsg* msg = curl_multi_info_read(multi, &msgs_remaining);
    if((msg != nullptr) && (msg->msg == CURLMSG_DONE))
    {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &result.response_status);
        const CURLcode curl_error = msg->data.result;
        result.completed_successfully = (curl_error == CURLE_OK);
        if(error_buf[0] != '\0')
        {
            result.error_message = error_buf;
        }
        else if(curl_error != CURLE_OK)
        {
            result.error_message = curl_easy_strerror(curl_error);
        }
    }
    else if(!abort.is_aborting())
    {
        if(msg == nullptr)
            LOG_WARN("Received unexpected info read result from curl: Null message");
        else
            LOG_WARN("Received unexpected info read result from curl: Message type %d", int(msg->msg));
    }

    curl_slist_free_all(header_list);
    curl_multi_remove_handle(multi, curl);
    curl_easy_cleanup(curl);
    curl_multi_cleanup(multi);
    return result;
}

static CURL* make_curl_easy(CURLM* multi, const std::string& url, char* error_buf)
{
    CURL* curl = curl_easy_init();
    if(!curl)
    {
        curl_multi_cleanup(multi);
        return nullptr;
    }
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, error_buf);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "foo_openlyrics/" OPENLYRICS_VERSION);
    curl_easy_setopt(curl, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0);
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    return curl;
}

static curl_slist* build_header_list(const std::vector<http::Header>& headers)
{
    curl_slist* list = nullptr;
    for(const auto& h : headers)
    {
        const std::string header_str = h.name + ": " + h.value;
        list = curl_slist_append(list, header_str.c_str());
    }
    return list;
}

http::Result http::get_http2(const std::string& url, abort_callback& abort)
{
    CURLM* multi = curl_multi_init();
    if(!multi)
    {
        Result result = {};
        result.error_message = "Failed to initialise curl-multi handle";
        return result;
    }
    char error_buf[CURL_ERROR_SIZE] = {};
    CURL* curl = make_curl_easy(multi, url, error_buf);
    if(!curl)
    {
        Result result = {};
        result.error_message = "Failed to initialise curl-easy handle";
        return result;
    }
    return curl_perform(curl, multi, nullptr, error_buf, abort);
}

http::Result http::get_request(const std::string& url,
                                const std::vector<Header>& headers,
                                abort_callback& abort)
{
    CURLM* multi = curl_multi_init();
    if(!multi)
    {
        Result result = {};
        result.error_message = "Failed to initialise curl-multi handle";
        return result;
    }
    char error_buf[CURL_ERROR_SIZE] = {};
    CURL* curl = make_curl_easy(multi, url, error_buf);
    if(!curl)
    {
        Result result = {};
        result.error_message = "Failed to initialise curl-easy handle";
        return result;
    }
    curl_slist* header_list = build_header_list(headers);
    return curl_perform(curl, multi, header_list, error_buf, abort);
}

http::Result http::post_request(const std::string& url,
                                 const std::vector<Header>& headers,
                                 const std::string& body,
                                 const std::string& content_type,
                                 abort_callback& abort)
{
    CURLM* multi = curl_multi_init();
    if(!multi)
    {
        Result result = {};
        result.error_message = "Failed to initialise curl-multi handle";
        return result;
    }
    char error_buf[CURL_ERROR_SIZE] = {};
    CURL* curl = make_curl_easy(multi, url, error_buf);
    if(!curl)
    {
        Result result = {};
        result.error_message = "Failed to initialise curl-easy handle";
        return result;
    }
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)body.size());

    std::vector<Header> all_headers = headers;
    if(!content_type.empty())
        all_headers.push_back({"Content-Type", content_type});
    curl_slist* header_list = build_header_list(all_headers);
    return curl_perform(curl, multi, header_list, error_buf, abort);
}
