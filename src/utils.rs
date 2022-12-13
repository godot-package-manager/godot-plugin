pub fn send_get_request(url: String) -> String {
    reqwest::blocking::get(url).unwrap().text().unwrap()
}
