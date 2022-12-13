pub fn send_get_request(url: &String) -> String {
    reqwest::blocking::get(url).unwrap().text().unwrap()
}

pub fn send_get_request_bin(url: &String) -> Vec<u8> {
    reqwest::blocking::get(url)
        .unwrap()
        .bytes()
        .unwrap()
        .to_vec()
}
